// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

package enum StagingOwnershipRegistryError: LocalizedError {
    case unreadable(underlying: Error)
    case malformed(underlying: Error)
    case encoding(underlying: Error)
    case persistence(underlying: Error)

    package var errorDescription: String? {
        switch self {
        case .unreadable: return "PulseFiles could not read its staging recovery metadata."
        case .malformed: return "PulseFiles found damaged staging recovery metadata and left it unchanged for recovery."
        case .encoding: return "PulseFiles could not encode staging recovery metadata."
        case .persistence: return "PulseFiles could not durably save staging recovery metadata."
        }
    }
}

package enum StagingOperationState: String, Codable, Sendable {
    case active
    case completed
}

package struct StagingOwnershipRecord: Codable, Equatable, Sendable {
    package let operationID: UUID
    package let stagingURL: URL
    package let createdAt: Date
    package let destinationURL: URL
    package let stagingIdentity: String
    package let destinationIdentity: String
    package var state: StagingOperationState
}

/// Persists the minimum durable evidence needed to distinguish PulseFiles'
/// private transfer directories from similarly named user content.
package final class StagingOwnershipRegistry: @unchecked Sendable {
    private struct Document: Codable {
        var records: [StagingOwnershipRecord] = []
        var didReviewLegacyNames = false
    }

    package static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("PulseFiles/StagingOwnership.json")
    }

    private let url: URL
    private let readData: () throws -> Data?
    private let encode: (Document) throws -> Data
    private let persist: (Data) throws -> Void
    private let lock = NSLock()

    package init(
        url: URL = StagingOwnershipRegistry.defaultURL,
        fileManager: FileManager = .default,
        readData: (() throws -> Data?)? = nil,
        encode: ((StagingOwnershipRecord) throws -> Void)? = nil,
        persist: ((Data) throws -> Void)? = nil
    ) {
        self.url = url
        self.readData = readData ?? {
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }
        self.encode = { document in
            // The record hook permits deterministic encoder-failure coverage
            // without exposing the private on-disk document type.
            for record in document.records { try encode?(record) }
            return try JSONEncoder().encode(document)
        }
        self.persist = persist ?? { data in
            try Self.persistAtomicallyAndDurably(data, to: url, fileManager: fileManager)
        }
    }

    package var records: [StagingOwnershipRecord] { get throws { try withDocument { $0.records } } }

    package func register(_ record: StagingOwnershipRecord) throws {
        try update { document in
            document.records.removeAll { $0.operationID == record.operationID }
            document.records.append(record)
        }
    }

    package func setState(_ state: StagingOperationState, operationID: UUID) throws {
        try update { document in
            guard let index = document.records.firstIndex(where: { $0.operationID == operationID }) else { return }
            document.records[index].state = state
        }
    }

    package func remove(operationID: UUID) throws { try update { $0.records.removeAll { $0.operationID == operationID } } }

    @discardableResult
    package func prune(keeping operationIDs: Set<UUID>) throws -> Int {
        var removed = 0
        try update { document in
            let original = document.records.count
            document.records.removeAll { !operationIDs.contains($0.operationID) }
            removed = original - document.records.count
        }
        return removed
    }

    package func hasReviewedLegacyNames() throws -> Bool { try withDocument { $0.didReviewLegacyNames } }
    package func markLegacyNamesReviewed() throws { try update { $0.didReviewLegacyNames = true } }

    private func withDocument<T>(_ body: (Document) -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        return body(try load())
    }

    private func update(_ body: (inout Document) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var document = try load()
        body(&document)
        let data: Data
        do { data = try encode(document) }
        catch { throw StagingOwnershipRegistryError.encoding(underlying: error) }
        do { try persist(data) }
        catch { throw StagingOwnershipRegistryError.persistence(underlying: error) }
    }

    private func load() throws -> Document {
        let data: Data
        do {
            guard let existing = try readData() else { return Document() }
            data = existing
        } catch {
            DiagnosticLogger.log(.error, category: "StagingOwnership", "Staging recovery metadata is unreadable; preserving the existing document.")
            throw StagingOwnershipRegistryError.unreadable(underlying: error)
        }
        do { return try JSONDecoder().decode(Document.self, from: data) }
        catch {
            DiagnosticLogger.log(.error, category: "StagingOwnership", "Staging recovery metadata is malformed; preserving the existing document for explicit recovery. byteCount=\(data.count)")
            throw StagingOwnershipRegistryError.malformed(underlying: error)
        }
    }

    private static func persistAtomicallyAndDurably(_ data: Data, to url: URL, fileManager: FileManager) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        #if os(macOS)
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let directoryDescriptor = Darwin.open(parent.path, O_RDONLY)
        guard directoryDescriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(directoryDescriptor) }
        guard Darwin.fsync(directoryDescriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

package struct StagingCleanupCandidate: Equatable, Sendable {
    package let record: StagingOwnershipRecord
    package let byteCount: Int64
}

package struct StagingCleanupInventory: Equatable, Sendable {
    package let candidates: [StagingCleanupCandidate]
    package let legacyItemsForReview: [URL]
    package var totalByteCount: Int64 { candidates.reduce(0) { $0 + $1.byteCount } }
}

package struct StagingCleanupFailure: Sendable {
    package let url: URL
    package let message: String
}

package struct StagingCleanupResult: Sendable {
    package let removed: [URL]
    package let failures: [StagingCleanupFailure]
}

package final class StagingCleanupService: @unchecked Sendable {
    package static let conservativeAutomaticAge: TimeInterval = 7 * 24 * 60 * 60

    private let registry: StagingOwnershipRegistry
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy
    private let identity: (URL) -> String?
    private let remove: (URL) throws -> Void
    private let legacyReviewDirectories: () -> [URL]

    package init(
        registry: StagingOwnershipRegistry = StagingOwnershipRegistry(),
        fileManager: FileManager = .default,
        accessPolicy: SandboxFileAccessPolicy = .current,
        identity: @escaping (URL) -> String? = StagingCleanupService.resourceIdentity,
        remove: ((URL) throws -> Void)? = nil,
        legacyReviewDirectories: @escaping () -> [URL] = { [] }
    ) {
        self.registry = registry
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.identity = identity
        self.remove = remove ?? fileManager.removeItem(at:)
        self.legacyReviewDirectories = legacyReviewDirectories
    }

    package static func resourceIdentity(_ url: URL) -> String? {
        guard let value = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return nil }
        return String(reflecting: value)
    }

    package func inventory(olderThan cutoff: Date? = nil, includeLegacyReview: Bool = true) throws -> StagingCleanupInventory {
        var candidates: [StagingCleanupCandidate] = []
        var retained = Set<UUID>()
        for record in try registry.records {
            guard fileManager.fileExists(atPath: record.stagingURL.path) else { continue }
            retained.insert(record.operationID)
            guard record.state == .completed, cutoff.map({ record.createdAt < $0 }) ?? true else { continue }
            guard identity(record.stagingURL) == record.stagingIdentity,
                  identity(record.destinationURL) == record.destinationIdentity else { continue }
            candidates.append(.init(record: record, byteCount: allocatedSize(of: record.stagingURL)))
        }
        _ = try registry.prune(keeping: retained)
        return .init(candidates: candidates, legacyItemsForReview: includeLegacyReview ? try legacyItems() : [])
    }

    package func cleanup(_ candidates: [StagingCleanupCandidate]) async -> StagingCleanupResult {
        await Task.detached(priority: .utility) { [self] in
            var removed: [URL] = []
            var failures: [StagingCleanupFailure] = []
            for candidate in candidates {
                let record = candidate.record
                do {
                    guard try registry.records.contains(where: { $0.operationID == record.operationID && $0.state == .completed }) else { continue }
                    guard identity(record.stagingURL) == record.stagingIdentity,
                          identity(record.destinationURL) == record.destinationIdentity else { continue }
                    try accessPolicy.validateAccess(to: record.stagingURL)
                    try accessPolicy.validateDestinationAccess(to: record.stagingURL)
                    try remove(record.stagingURL)
                    try registry.remove(operationID: record.operationID)
                    removed.append(record.stagingURL)
                } catch {
                    failures.append(.init(url: record.stagingURL, message: error.localizedDescription))
                }
            }
            return .init(removed: removed, failures: failures)
        }.value
    }

    package func cleanupOnStartup(now: Date = Date()) async -> StagingCleanupResult {
        do {
            let inventory = try inventory(olderThan: now.addingTimeInterval(-Self.conservativeAutomaticAge), includeLegacyReview: false)
            return await cleanup(inventory.candidates)
        } catch {
            return .init(removed: [], failures: [.init(url: StagingOwnershipRegistry.defaultURL, message: error.localizedDescription)])
        }
    }

    /// Prefix-only matches are deliberately review-only and are never cleanup candidates.
    private func legacyItems() throws -> [URL] {
        guard try !registry.hasReviewedLegacyNames() else { return [] }
        let parents = Set(try registry.records.map { $0.destinationURL.standardizedFileURL } + legacyReviewDirectories().map(\.standardizedFileURL))
        let prefixes = [".pulsefiles-copy-", ".pulsefiles-move-", ".pulsefiles-backup-"]
        let matches = parents.flatMap { parent in
            (try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil))?.filter { item in
                prefixes.contains { item.lastPathComponent.hasPrefix($0) }
            } ?? []
        }
        try registry.markLegacyNamesReviewed()
        return matches.sorted { $0.path < $1.path }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

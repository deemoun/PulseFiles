import Foundation

enum StagingOperationState: String, Codable, Sendable {
    case active
    case completed
}

struct StagingOwnershipRecord: Codable, Equatable, Sendable {
    let operationID: UUID
    let stagingURL: URL
    let createdAt: Date
    let destinationURL: URL
    let stagingIdentity: String
    let destinationIdentity: String
    var state: StagingOperationState
}

/// Persists the minimum durable evidence needed to distinguish PulseFiles'
/// private transfer directories from similarly named user content.
final class StagingOwnershipRegistry: @unchecked Sendable {
    private struct Document: Codable {
        var records: [StagingOwnershipRecord] = []
        var didReviewLegacyNames = false
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("PulseFiles/StagingOwnership.json")
    }

    private let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(url: URL = StagingOwnershipRegistry.defaultURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    var records: [StagingOwnershipRecord] { withDocument { $0.records } }

    func register(_ record: StagingOwnershipRecord) {
        update { document in
            document.records.removeAll { $0.operationID == record.operationID }
            document.records.append(record)
        }
    }

    func setState(_ state: StagingOperationState, operationID: UUID) {
        update { document in
            guard let index = document.records.firstIndex(where: { $0.operationID == operationID }) else { return }
            document.records[index].state = state
        }
    }

    func remove(operationID: UUID) { update { $0.records.removeAll { $0.operationID == operationID } } }

    @discardableResult
    func prune(keeping operationIDs: Set<UUID>) -> Int {
        var removed = 0
        update { document in
            let original = document.records.count
            document.records.removeAll { !operationIDs.contains($0.operationID) }
            removed = original - document.records.count
        }
        return removed
    }

    var didReviewLegacyNames: Bool {
        get { withDocument { $0.didReviewLegacyNames } }
        set { update { $0.didReviewLegacyNames = newValue } }
    }

    private func withDocument<T>(_ body: (Document) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(load())
    }

    private func update(_ body: (inout Document) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var document = load()
        body(&document)
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load() -> Document {
        guard let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(Document.self, from: data) else { return Document() }
        return document
    }
}

struct StagingCleanupCandidate: Equatable, Sendable {
    let record: StagingOwnershipRecord
    let byteCount: Int64
}

struct StagingCleanupInventory: Equatable, Sendable {
    let candidates: [StagingCleanupCandidate]
    let legacyItemsForReview: [URL]
    var totalByteCount: Int64 { candidates.reduce(0) { $0 + $1.byteCount } }
}

struct StagingCleanupFailure: Sendable {
    let url: URL
    let message: String
}

struct StagingCleanupResult: Sendable {
    let removed: [URL]
    let failures: [StagingCleanupFailure]
}

final class StagingCleanupService: @unchecked Sendable {
    static let conservativeAutomaticAge: TimeInterval = 7 * 24 * 60 * 60

    private let registry: StagingOwnershipRegistry
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy
    private let identity: (URL) -> String?
    private let remove: (URL) throws -> Void
    private let legacyReviewDirectories: () -> [URL]

    init(
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

    static func resourceIdentity(_ url: URL) -> String? {
        guard let value = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return nil }
        return String(reflecting: value)
    }

    func inventory(olderThan cutoff: Date? = nil, includeLegacyReview: Bool = true) -> StagingCleanupInventory {
        var candidates: [StagingCleanupCandidate] = []
        var retained = Set<UUID>()
        for record in registry.records {
            guard fileManager.fileExists(atPath: record.stagingURL.path) else { continue }
            retained.insert(record.operationID)
            guard record.state == .completed, cutoff.map({ record.createdAt < $0 }) ?? true else { continue }
            guard identity(record.stagingURL) == record.stagingIdentity,
                  identity(record.destinationURL) == record.destinationIdentity else { continue }
            candidates.append(.init(record: record, byteCount: allocatedSize(of: record.stagingURL)))
        }
        _ = registry.prune(keeping: retained)
        return .init(candidates: candidates, legacyItemsForReview: includeLegacyReview ? legacyItems() : [])
    }

    func cleanup(_ candidates: [StagingCleanupCandidate]) async -> StagingCleanupResult {
        await Task.detached(priority: .utility) { [self] in
            var removed: [URL] = []
            var failures: [StagingCleanupFailure] = []
            for candidate in candidates {
                let record = candidate.record
                guard registry.records.contains(where: { $0.operationID == record.operationID && $0.state == .completed }) else { continue }
                guard identity(record.stagingURL) == record.stagingIdentity,
                      identity(record.destinationURL) == record.destinationIdentity else { continue }
                do {
                    try accessPolicy.validateAccess(to: record.stagingURL)
                    try accessPolicy.validateDestinationAccess(to: record.stagingURL)
                    try remove(record.stagingURL)
                    registry.remove(operationID: record.operationID)
                    removed.append(record.stagingURL)
                } catch {
                    failures.append(.init(url: record.stagingURL, message: error.localizedDescription))
                }
            }
            return .init(removed: removed, failures: failures)
        }.value
    }

    func cleanupOnStartup(now: Date = Date()) async -> StagingCleanupResult {
        let inventory = inventory(olderThan: now.addingTimeInterval(-Self.conservativeAutomaticAge), includeLegacyReview: false)
        return await cleanup(inventory.candidates)
    }

    /// Prefix-only matches are deliberately review-only and are never cleanup candidates.
    private func legacyItems() -> [URL] {
        guard !registry.didReviewLegacyNames else { return [] }
        let parents = Set(registry.records.map { $0.destinationURL.standardizedFileURL } + legacyReviewDirectories().map(\.standardizedFileURL))
        let prefixes = [".pulsefiles-copy-", ".pulsefiles-move-", ".pulsefiles-backup-"]
        let matches = parents.flatMap { parent in
            (try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil))?.filter { item in
                prefixes.contains { item.lastPathComponent.hasPrefix($0) }
            } ?? []
        }
        registry.didReviewLegacyNames = true
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

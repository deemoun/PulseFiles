// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum ArchiveOperationError: LocalizedError, Equatable {
    case unsupportedFormat, malformedArchive
    case unsafePath(String), unsafeLink(String), duplicateOutputPath(String)
    case itemLimitExceeded(Int), expandedByteLimitExceeded(Int64), nestingLimitExceeded(String)

    package var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "This archive format or compression method is not supported safely.".localized
        case .malformedArchive: return "The archive is damaged or incomplete.".localized
        case .unsafePath(let path): return "The archive contains an unsafe path: %@.".localized(with: path)
        case .unsafeLink(let path): return "The archive contains an unsafe link: %@.".localized(with: path)
        case .duplicateOutputPath(let path): return "The archive contains the output path more than once: %@.".localized(with: path)
        case .itemLimitExceeded(let limit): return "The archive exceeds the %@ item safety limit.".localized(with: String(limit))
        case .expandedByteLimitExceeded(let limit): return "The archive exceeds the %@ expanded-byte safety limit.".localized(with: ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))
        case .nestingLimitExceeded(let path): return "The archive path is nested too deeply: %@.".localized(with: path)
        }
    }
}

package enum ArchiveStreamPoint: Equatable { case createRead, createWrite, extractMetadataRead, extractRead, extractWrite }

/// Minimal, audited stored-ZIP reader/writer. Payload bytes always pass through a
/// fixed-size buffer; only names and central-directory fields remain in memory.
package final class ArchiveOperationService {
    package typealias StreamHook = (ArchiveStreamPoint, Int) throws -> Void
    private struct Source { let url: URL; let path: String; let size: UInt64; let isDirectory: Bool }
    private struct Central { let path: String; let size: UInt32; let crc: UInt32; let offset: UInt32; let isDirectory: Bool }
    private struct Entry { let path: String; let dataOffset: UInt64; let size: UInt64; let crc: UInt32; let isDirectory: Bool }
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let mutations: FileMutationEngine
    private let bufferSize: Int
    private let streamHook: StreamHook?

    package init(fileManager: FileOperationFileManaging = FileManager.default, accessPolicy: SandboxFileAccessPolicy = .current,
                 pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationPreflightValidator.defaultPathSafetyState,
                 stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry(),
                 streamBufferSize: Int = 64 * 1024, streamHook: StreamHook? = nil,
                 mutations: FileMutationEngine? = nil) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        let descriptor = DescriptorRelativeFileOperator(fileManager: fileManager)
        let validator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy,
                                                        pathSafetyStateProvider: pathSafetyStateProvider)
        self.mutations = mutations ?? validator.mutationEngine(fileManager: fileManager, accessPolicy: accessPolicy,
                                                               descriptorOperator: descriptor, stagingRegistry: stagingRegistry)
        self.bufferSize = max(1, streamBufferSize)
        self.streamHook = streamHook
    }

    package func create(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        guard request.format == .zip else { throw ArchiveOperationError.unsupportedFormat }
        try accessPolicy.validateDestinationAccess(to: request.destinationURL)
        for source in request.sources { try accessPolicy.validateAccess(to: source) }
        if fileManager.fileExists(atPath: request.destinationURL.path) { throw FileOperationError.destinationExists(request.destinationURL) }
        var sources: [Source] = [], totalBytes: UInt64 = 0
        for source in request.sources {
            guard fileManager.fileExists(atPath: source.path) else { throw FileOperationError.sourceMissing(source) }
            try collect(source, relative: source.lastPathComponent, limits: request.limits, sources: &sources, bytes: &totalBytes)
        }
        guard sources.count <= Int(UInt16.max) else { throw ArchiveOperationError.itemLimitExceeded(Int(UInt16.max)) }
        let staging = try mutations.makeStagingArea(in: request.destinationURL.deletingLastPathComponent(), prefix: "archive")
        let temporary = staging.directory.appendingPathComponent("item")
        do {
            try mutations.createFile(temporary)
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            var central: [Central] = [], completedBytes: UInt64 = 0
            for (index, source) in sources.enumerated() {
                try Task.checkCancellation()
                let offset = try zip32(output.offsetInFile)
                let name = Data(source.path.utf8)
                guard name.count <= Int(UInt16.max), source.size <= UInt64(UInt32.max) else { throw ArchiveOperationError.unsupportedFormat }
                var header = Data(); header.le32(0x04034b50); header.le16(20); header.le16(source.isDirectory ? 0x0800 : 0x0808)
                header.le16(0); header.le16(0); header.le16(0); header.le32(0); header.le32(0); header.le32(0)
                header.le16(UInt16(name.count)); header.le16(0); header.append(name)
                try write(header, to: output, point: .createWrite)
                var crc = CRC32(), written: UInt64 = 0
                if !source.isDirectory {
                    let input = try FileHandle(forReadingFrom: source.url); defer { try? input.close() }
                    while written < source.size {
                        try Task.checkCancellation()
                        let count = Int(min(UInt64(bufferSize), source.size - written))
                        let chunk = try input.read(upToCount: count) ?? Data()
                        try streamHook?(.createRead, chunk.count)
                        guard !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                        crc.update(chunk); try write(chunk, to: output, point: .createWrite)
                        written = try add(written, UInt64(chunk.count)); completedBytes = try add(completedBytes, UInt64(chunk.count))
                        await progressHandler?(.init(currentItemName: source.path, completedCount: index, totalCount: sources.count,
                                                     completedByteCount: try int64(completedBytes), totalByteCount: try int64(totalBytes)))
                    }
                    var descriptor = Data(); descriptor.le32(0x08074b50); descriptor.le32(crc.value); descriptor.le32(UInt32(written)); descriptor.le32(UInt32(written))
                    try write(descriptor, to: output, point: .createWrite)
                }
                central.append(.init(path: source.path, size: UInt32(written), crc: crc.value, offset: offset, isDirectory: source.isDirectory))
                await progressHandler?(.init(currentItemName: source.path, completedCount: index + 1, totalCount: sources.count,
                                             completedByteCount: try int64(completedBytes), totalByteCount: try int64(totalBytes)))
            }
            let centralOffset = try zip32(output.offsetInFile)
            for record in central { try write(centralRecord(record), to: output, point: .createWrite) }
            let centralSize64 = output.offsetInFile - UInt64(centralOffset), centralSize = try zip32(centralSize64)
            var end = Data(); end.le32(0x06054b50); end.le16(0); end.le16(0); end.le16(UInt16(central.count)); end.le16(UInt16(central.count))
            end.le32(centralSize); end.le32(centralOffset); end.le16(0)
            try write(end, to: output, point: .createWrite); try output.synchronize(); try output.close()
            _ = try mutations.publish(temporary, to: request.destinationURL, staging: staging)
            return .init(completedItems: [request.destinationURL], skippedItems: [], failedItems: [],
                         cleanupWarnings: mutations.cleanup(staging), wasCancelled: false)
        } catch {
            let warnings = mutations.cleanup(staging)
            if !warnings.isEmpty {
                return .init(completedItems: [], skippedItems: [], failedItems: [.init(url: request.destinationURL, error: error)],
                             cleanupWarnings: warnings, wasCancelled: error is CancellationError)
            }
            if error is CancellationError { return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true) }
            throw error
        }
    }

    package func extract(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try accessPolicy.validateAccess(to: request.archiveURL); try accessPolicy.validateAccess(to: request.destinationDirectory)
        let archive = try FileHandle(forReadingFrom: request.archiveURL); defer { try? archive.close() }
        let entries = try parse(archive, limits: request.limits)
        let totalBytes = entries.reduce(UInt64(0)) { $0 + $1.size }
        let staging = try mutations.makeStagingArea(in: request.destinationDirectory, prefix: "extract")
        var completed: [URL] = [], skipped: [URL] = [], published: [FileMutationEngine.Publication] = []
        do {
            var completedBytes: UInt64 = 0
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation(); let staged = staging.directory.appendingPathComponent(entry.path)
                if entry.isDirectory { try mutations.createDirectoryTree(staged) }
                else {
                    try mutations.createDirectoryTree(staged.deletingLastPathComponent())
                    try mutations.createFile(staged)
                    do {
                        let output = try FileHandle(forWritingTo: staged); defer { try? output.close() }
                        try archive.seek(toOffset: entry.dataOffset); var remaining = entry.size; var crc = CRC32()
                        while remaining > 0 {
                            try Task.checkCancellation(); let count = Int(min(UInt64(bufferSize), remaining))
                            let chunk = try archive.read(upToCount: count) ?? Data(); try streamHook?(.extractRead, chunk.count)
                            guard !chunk.isEmpty else { throw ArchiveOperationError.malformedArchive }
                            crc.update(chunk); try write(chunk, to: output, point: .extractWrite)
                            remaining -= UInt64(chunk.count); completedBytes = try add(completedBytes, UInt64(chunk.count))
                            await progressHandler?(.init(currentItemName: entry.path, completedCount: index, totalCount: entries.count,
                                                         completedByteCount: try int64(completedBytes), totalByteCount: try int64(totalBytes)))
                        }
                        try output.synchronize(); guard crc.value == entry.crc else { throw ArchiveOperationError.malformedArchive }
                    } catch { try? mutations.remove(staged); throw error }
                }
                await progressHandler?(.init(currentItemName: entry.path, completedCount: index + 1, totalCount: entries.count,
                                             completedByteCount: try int64(completedBytes), totalByteCount: try int64(totalBytes)))
            }
            let children = try fileManager.contentsOfDirectory(at: staging.directory, includingPropertiesForKeys: nil, options: [])
                .filter { $0 != staging.marker }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            var decisions: [(URL, URL, FileConflictResolution)] = []
            for child in children {
                let destination = request.destinationDirectory.appendingPathComponent(child.lastPathComponent)
                let decision: FileConflictResolution = fileManager.fileExists(atPath: destination.path) ? await conflictHandler(destination) : .replace
                if decision == .cancel { throw CancellationError() }
                let resolved = (decision == .keepBoth || decision == .applyToRemainingKeepBoth) ? FileOperationService.keepBothDestination(for: destination, fileExists: { self.fileManager.fileExists(atPath: $0.path) }) : destination
                decisions.append((child, resolved, decision))
            }
            for (child, destination, decision) in decisions {
                try Task.checkCancellation(); if decision == .skip || decision == .applyToRemainingSkip { skipped.append(destination); continue }
                published.append(try mutations.publish(child, to: destination, staging: staging)); completed.append(destination)
            }
            let warnings = mutations.cleanup(staging)
            return .init(completedItems: completed, skippedItems: skipped, failedItems: [], cleanupWarnings: warnings, wasCancelled: false)
        } catch {
            let rollback = mutations.rollback(published)
            var warnings = rollback.warnings
            completed.removeAll { !rollback.retainedDestinations.contains($0.standardizedFileURL) }
            if warnings.isEmpty { warnings.append(contentsOf: mutations.cleanup(staging)) }
            if !warnings.isEmpty { return .init(completedItems: completed, skippedItems: skipped, failedItems: [.init(url: request.archiveURL, error: error)], cleanupWarnings: warnings, wasCancelled: error is CancellationError) }
            if error is CancellationError { return .init(completedItems: [], skippedItems: skipped, failedItems: [], wasCancelled: true) }
            throw error
        }
    }

    private func collect(_ url: URL, relative: String, limits: ArchiveSafetyLimits, sources: inout [Source], bytes: inout UInt64) throws {
        guard limits.maximumExpandedBytes >= 0 else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true { throw ArchiveOperationError.unsafeLink(relative) }
        if relative.split(separator: "/").count > limits.maximumPathDepth { throw ArchiveOperationError.nestingLimitExceeded(relative) }
        guard sources.count < limits.maximumItemCount else { throw ArchiveOperationError.itemLimitExceeded(limits.maximumItemCount) }
        if values.isDirectory == true {
            sources.append(.init(url: url, path: relative + "/", size: 0, isDirectory: true))
            for child in try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: []) { try collect(child, relative: relative + "/" + child.lastPathComponent, limits: limits, sources: &sources, bytes: &bytes) }
        } else {
            guard let rawSize = values.fileSize, rawSize >= 0 else { throw CocoaError(.fileReadUnknown) }
            bytes = try add(bytes, UInt64(rawSize)); guard bytes <= UInt64(limits.maximumExpandedBytes) else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
            sources.append(.init(url: url, path: relative, size: UInt64(rawSize), isDirectory: false))
        }
    }

    private func parse(_ file: FileHandle, limits: ArchiveSafetyLimits) throws -> [Entry] {
        guard limits.maximumExpandedBytes >= 0 else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
        let length = try file.seekToEnd(); guard length >= 22 else { throw ArchiveOperationError.malformedArchive }
        let tailSize = min(length, 65_557); let tailOffset = length - tailSize; try file.seek(toOffset: tailOffset)
        let tail = try readExactly(file, count: Int(tailSize), point: .extractMetadataRead)
        guard let relativeEOCD = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.u32($0) == 0x06054b50 }) else { throw ArchiveOperationError.malformedArchive }
        let count = Int(tail.u16(relativeEOCD + 10)); guard count <= limits.maximumItemCount else { throw ArchiveOperationError.itemLimitExceeded(limits.maximumItemCount) }
        var cursor = UInt64(tail.u32(relativeEOCD + 16)), total: UInt64 = 0, outputs = Set<String>(), result: [Entry] = []
        for _ in 0..<count {
            try file.seek(toOffset: cursor); let fixed = try readExactly(file, count: 46, point: .extractMetadataRead)
            guard fixed.u32(0) == 0x02014b50 else { throw ArchiveOperationError.malformedArchive }
            let flags = fixed.u16(8), method = fixed.u16(10), crc = fixed.u32(16), size = UInt64(fixed.u32(24))
            let nameLength = Int(fixed.u16(28)), extra = Int(fixed.u16(30)), comment = Int(fixed.u16(32)), external = fixed.u32(38), local = UInt64(fixed.u32(42))
            guard flags & 1 == 0, method == 0 else { throw ArchiveOperationError.unsupportedFormat }
            let name = try readExactly(file, count: nameLength, point: .extractMetadataRead)
            guard let path = String(data: name, encoding: .utf8) else { throw ArchiveOperationError.unsupportedFormat }
            try validate(path, limits: limits); let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
            let key = normalized.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard outputs.insert(key).inserted else { throw ArchiveOperationError.duplicateOutputPath(path) }
            if (external >> 16) & 0xF000 == 0xA000 { throw ArchiveOperationError.unsafeLink(path) }
            total = try add(total, size); guard total <= UInt64(limits.maximumExpandedBytes) else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
            try file.seek(toOffset: local); let localHeader = try readExactly(file, count: 30, point: .extractMetadataRead)
            guard localHeader.u32(0) == 0x04034b50 else { throw ArchiveOperationError.malformedArchive }
            var dataOffset = try add(local, 30); dataOffset = try add(dataOffset, UInt64(localHeader.u16(26))); dataOffset = try add(dataOffset, UInt64(localHeader.u16(28)))
            guard dataOffset <= length, size <= length - dataOffset else { throw ArchiveOperationError.malformedArchive }
            result.append(.init(path: normalized, dataOffset: dataOffset, size: size, crc: crc, isDirectory: path.hasSuffix("/")))
            cursor = try add(cursor, UInt64(46 + nameLength + extra + comment)); guard cursor <= length else { throw ArchiveOperationError.malformedArchive }
        }
        return result
    }

    private func validate(_ path: String, limits: ArchiveSafetyLimits) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { throw ArchiveOperationError.unsafePath(path) }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else { throw ArchiveOperationError.unsafePath(path) }
        guard components.count <= limits.maximumPathDepth else { throw ArchiveOperationError.nestingLimitExceeded(path) }
        if components.first?.contains(":") == true { throw ArchiveOperationError.unsafePath(path) }
    }

    private func centralRecord(_ record: Central) -> Data {
        let name = Data(record.path.utf8); var data = Data(); data.le32(0x02014b50); data.le16(0x0314); data.le16(20); data.le16(record.isDirectory ? 0x0800 : 0x0808)
        data.le16(0); data.le16(0); data.le16(0); data.le32(record.crc); data.le32(record.size); data.le32(record.size); data.le16(UInt16(name.count)); data.le16(0); data.le16(0); data.le16(0); data.le16(0)
        data.le32(record.isDirectory ? 0x41ED0010 : 0x81A40000); data.le32(record.offset); data.append(name); return data
    }
    private func write(_ data: Data, to file: FileHandle, point: ArchiveStreamPoint) throws { try streamHook?(point, data.count); try file.write(contentsOf: data) }
    private func readExactly(_ file: FileHandle, count: Int, point: ArchiveStreamPoint) throws -> Data {
        guard count >= 0 else { throw ArchiveOperationError.malformedArchive }; var result = Data(); result.reserveCapacity(count)
        while result.count < count { let chunk = try file.read(upToCount: min(bufferSize, count - result.count)) ?? Data(); try streamHook?(point, chunk.count); guard !chunk.isEmpty else { throw ArchiveOperationError.malformedArchive }; result.append(chunk) }
        return result
    }
    private func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 { let (value, overflow) = lhs.addingReportingOverflow(rhs); guard !overflow else { throw ArchiveOperationError.malformedArchive }; return value }
    private func zip32(_ value: UInt64) throws -> UInt32 { guard value <= UInt64(UInt32.max) else { throw ArchiveOperationError.unsupportedFormat }; return UInt32(value) }
    private func int64(_ value: UInt64) throws -> Int64 { guard value <= UInt64(Int64.max) else { throw ArchiveOperationError.unsupportedFormat }; return Int64(value) }
    private func publishedIdentity(at url: URL) throws -> NSObjectProtocol { guard let value = try url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { throw CocoaError(.fileReadUnknown) }; return value }
}

private struct CRC32 {
    private var crc: UInt32 = 0xffffffff
    mutating func update(_ data: Data) { for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) } } }
    var value: UInt32 { crc ^ 0xffffffff }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 0xffff)); le16(UInt16(value >> 16)) }
    func valid(_ offset: Int, _ length: Int) -> Bool { offset >= 0 && length >= 0 && offset <= count && length <= count - offset }
    func u16(_ offset: Int) -> UInt16 { guard valid(offset, 2) else { return 0 }; return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}

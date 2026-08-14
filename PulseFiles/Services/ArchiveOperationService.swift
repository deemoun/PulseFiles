import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum ArchiveOperationError: LocalizedError, Equatable {
    case unsupportedFormat
    case malformedArchive
    case unsafePath(String)
    case unsafeLink(String)
    case duplicateOutputPath(String)
    case itemLimitExceeded(Int)
    case expandedByteLimitExceeded(Int64)
    case nestingLimitExceeded(String)

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

/// Minimal, audited ZIP reader/writer. Creation uses ZIP's stored method;
/// extraction accepts stored entries only. No process or shell is launched.
package final class ArchiveOperationService {
    private struct Entry { let path: String; let dataOffset: Int; let size: Int; let crc: UInt32; let isDirectory: Bool }
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    package init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager; self.accessPolicy = accessPolicy
    }

    package func create(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        guard request.format == .zip else { throw ArchiveOperationError.unsupportedFormat }
        try accessPolicy.validateDestinationAccess(to: request.destinationURL)
        for source in request.sources { try accessPolicy.validateAccess(to: source) }
        if fileManager.fileExists(atPath: request.destinationURL.path) { throw FileOperationError.destinationExists(request.destinationURL) }
        var records: [(String, Data, Bool, UInt32, UInt32)] = []
        var bytes: Int64 = 0
        for source in request.sources {
            guard fileManager.fileExists(atPath: source.path) else { throw FileOperationError.sourceMissing(source) }
            try collect(source, relative: source.lastPathComponent, limits: request.limits, records: &records, bytes: &bytes)
        }
        let temporary = request.destinationURL.deletingLastPathComponent().appendingPathComponent(".pulsefiles-archive-\(UUID().uuidString)")
        do {
            var output = Data(); var central = Data()
            guard records.count <= Int(UInt16.max) else { throw ArchiveOperationError.itemLimitExceeded(Int(UInt16.max)) }
            for (index, record) in records.enumerated() {
                try Task.checkCancellation()
                let name = Data(record.0.utf8)
                guard name.count <= Int(UInt16.max), record.1.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else { throw ArchiveOperationError.unsupportedFormat }
                let offset = UInt32(output.count)
                output.le32(0x04034b50); output.le16(20); output.le16(0x0800); output.le16(0); output.le16(0); output.le16(0)
                output.le32(record.3); output.le32(UInt32(record.1.count)); output.le32(UInt32(record.1.count)); output.le16(UInt16(name.count)); output.le16(0); output.append(name); output.append(record.1)
                central.le32(0x02014b50); central.le16(0x0314); central.le16(20); central.le16(0x0800); central.le16(0); central.le16(0); central.le16(0)
                central.le32(record.3); central.le32(UInt32(record.1.count)); central.le32(UInt32(record.1.count)); central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
                central.le32(record.2 ? 0x41ED0010 : 0x81A40000); central.le32(offset); central.append(name)
                await progressHandler?(.init(currentItemName: record.0, completedCount: index + 1, totalCount: records.count, completedByteCount: Int64(output.count), totalByteCount: bytes))
            }
            guard output.count <= Int(UInt32.max), central.count <= Int(UInt32.max) else { throw ArchiveOperationError.unsupportedFormat }
            let centralOffset = UInt32(output.count); output.append(central)
            output.le32(0x06054b50); output.le16(0); output.le16(0); output.le16(UInt16(records.count)); output.le16(UInt16(records.count)); output.le32(UInt32(central.count)); output.le32(centralOffset); output.le16(0)
            try output.write(to: temporary, options: .atomic)
            try fileManager.moveItem(at: temporary, to: request.destinationURL)
            return .init(completedItems: [request.destinationURL], skippedItems: [], failedItems: [], wasCancelled: false)
        } catch {
            try? fileManager.removeItem(at: temporary)
            if error is CancellationError { return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true) }
            throw error
        }
    }

    package func extract(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try accessPolicy.validateAccess(to: request.archiveURL); try accessPolicy.validateAccess(to: request.destinationDirectory)
        let data = try Data(contentsOf: request.archiveURL, options: .mappedIfSafe)
        let entries = try parse(data, limits: request.limits)
        let staging = request.destinationDirectory.appendingPathComponent(".pulsefiles-extract-\(UUID().uuidString)", isDirectory: true)
        try accessPolicy.validateDestinationAccess(to: staging)
        var completed: [URL] = [], skipped: [URL] = []
        var backups: [(destination: URL, backup: URL)] = []
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                let staged = staging.appendingPathComponent(entry.path)
                if entry.isDirectory { try fileManager.createDirectory(at: staged, withIntermediateDirectories: true) }
                else {
                    try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let payload = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.size))
                    guard Self.crc32(payload) == entry.crc else { throw ArchiveOperationError.malformedArchive }
                    try payload.write(to: staged, options: .withoutOverwriting)
                }
                await progressHandler?(.init(currentItemName: entry.path, completedCount: index + 1, totalCount: entries.count))
            }
            // Preflight every top-level conflict before moving any staged output.
            let children = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            var decisions: [(URL, URL, FileConflictResolution)] = []
            for child in children {
                let destination = request.destinationDirectory.appendingPathComponent(child.lastPathComponent)
                let decision: FileConflictResolution = fileManager.fileExists(atPath: destination.path) ? await conflictHandler(destination) : .replace
                if decision == .cancel { throw CancellationError() }
                let resolvedDestination = (decision == .keepBoth || decision == .applyToRemainingKeepBoth)
                    ? FileOperationService.keepBothDestination(for: destination, fileExists: { self.fileManager.fileExists(atPath: $0.path) })
                    : destination
                decisions.append((child, resolvedDestination, decision))
            }
            for (child, destination, decision) in decisions {
                try Task.checkCancellation()
                if decision == .skip || decision == .applyToRemainingSkip { skipped.append(destination); continue }
                if fileManager.fileExists(atPath: destination.path) {
                    let backupDirectory = staging.appendingPathComponent(".replacement-backups", isDirectory: true)
                    try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                    let backup = backupDirectory.appendingPathComponent(UUID().uuidString)
                    try fileManager.moveItem(at: destination, to: backup)
                    backups.append((destination, backup))
                }
                do { try fileManager.moveItem(at: child, to: destination); completed.append(destination) }
                catch {
                    if let backup = backups.last, backup.destination == destination {
                        try? fileManager.moveItem(at: backup.backup, to: destination); backups.removeLast()
                    }
                    throw error
                }
            }
            try fileManager.removeItem(at: staging)
            return .init(completedItems: completed, skippedItems: skipped, failedItems: [], wasCancelled: false)
        } catch {
            // No incomplete replacement is published: move new outputs back to
            // staging and restore every original destination before cleanup.
            for backup in backups.reversed() {
                if fileManager.fileExists(atPath: backup.destination.path) { try? fileManager.removeItem(at: backup.destination) }
                try? fileManager.moveItem(at: backup.backup, to: backup.destination)
            }
            try? fileManager.removeItem(at: staging)
            if error is CancellationError { return .init(completedItems: completed, skippedItems: skipped, failedItems: [], wasCancelled: true) }
            throw error
        }
    }

    private func collect(_ url: URL, relative: String, limits: ArchiveSafetyLimits, records: inout [(String, Data, Bool, UInt32, UInt32)], bytes: inout Int64) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw ArchiveOperationError.unsafeLink(relative) }
        if relative.split(separator: "/").count > limits.maximumPathDepth { throw ArchiveOperationError.nestingLimitExceeded(relative) }
        guard records.count < limits.maximumItemCount else { throw ArchiveOperationError.itemLimitExceeded(limits.maximumItemCount) }
        if values.isDirectory == true {
            records.append((relative + "/", Data(), true, 0, 0))
            for child in try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                try collect(child, relative: relative + "/" + child.lastPathComponent, limits: limits, records: &records, bytes: &bytes)
            }
        } else {
            let data = try Data(contentsOf: url); bytes += Int64(data.count)
            guard bytes <= limits.maximumExpandedBytes else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
            records.append((relative, data, false, Self.crc32(data), 0))
        }
    }

    private func parse(_ data: Data, limits: ArchiveSafetyLimits) throws -> [Entry] {
        guard data.count >= 22 else { throw ArchiveOperationError.malformedArchive }
        let searchStart = max(0, data.count - 65_557)
        guard let eocd = stride(from: data.count - 22, through: searchStart, by: -1).first(where: { data.u32($0) == 0x06054b50 }) else { throw ArchiveOperationError.malformedArchive }
        let count = Int(data.u16(eocd + 10)); guard count <= limits.maximumItemCount else { throw ArchiveOperationError.itemLimitExceeded(limits.maximumItemCount) }
        var cursor = Int(data.u32(eocd + 16)), total: Int64 = 0, outputs = Set<String>(), result: [Entry] = []
        for _ in 0..<count {
            guard data.valid(cursor, 46), data.u32(cursor) == 0x02014b50 else { throw ArchiveOperationError.malformedArchive }
            let flags = data.u16(cursor + 8), method = data.u16(cursor + 10), crc = data.u32(cursor + 16), size = Int(data.u32(cursor + 24))
            let nameLength = Int(data.u16(cursor + 28)), extra = Int(data.u16(cursor + 30)), comment = Int(data.u16(cursor + 32)), external = data.u32(cursor + 38), local = Int(data.u32(cursor + 42))
            guard flags & 1 == 0, method == 0, data.valid(cursor + 46, nameLength), let path = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8) else { throw ArchiveOperationError.unsupportedFormat }
            try validate(path, limits: limits)
            let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
            let outputKey = normalized.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard outputs.insert(outputKey).inserted else { throw ArchiveOperationError.duplicateOutputPath(path) }
            let unixMode = (external >> 16) & 0xF000; if unixMode == 0xA000 { throw ArchiveOperationError.unsafeLink(path) }
            total += Int64(size); guard total <= limits.maximumExpandedBytes else { throw ArchiveOperationError.expandedByteLimitExceeded(limits.maximumExpandedBytes) }
            guard data.valid(local, 30), data.u32(local) == 0x04034b50 else { throw ArchiveOperationError.malformedArchive }
            let offset = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28)); guard data.valid(offset, size) else { throw ArchiveOperationError.malformedArchive }
            result.append(.init(path: normalized, dataOffset: offset, size: size, crc: crc, isDirectory: path.hasSuffix("/")))
            cursor += 46 + nameLength + extra + comment
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

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) } }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 0xffff)); le16(UInt16(value >> 16)) }
    package func valid(_ offset: Int, _ length: Int) -> Bool { offset >= 0 && length >= 0 && offset <= count && length <= count - offset }
    package func u16(_ offset: Int) -> UInt16 { guard valid(offset, 2) else { return 0 }; return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    package func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}

import Foundation

enum BatchRenameError: LocalizedError, Equatable {
    case countMismatch
    case differentDirectories
    case duplicateSource(URL)
    case duplicateDestination(URL)
    case destinationCollision(URL)

    var errorDescription: String? {
        switch self {
        case .countMismatch: return "Every selected item must have a previewed destination name.".localized
        case .differentDirectories: return "Batch rename requires items from one folder.".localized
        case .duplicateSource: return "An item was selected more than once.".localized
        case .duplicateDestination(let url): return "More than one item would be renamed to %@.".localized(with: url.lastPathComponent)
        case .destinationCollision(let url): return "%@ already exists and is not part of this rename.".localized(with: url.lastPathComponent)
        }
    }
}

/// Batch rename cancellation is honored before mutation and between phases.
/// Once phase one starts, any cancellation/failure triggers best-effort rollback
/// to the original names. Rollback failures are reported as cleanup warnings and
/// the result is partial; PulseFiles never claims atomicity from FileManager.
final class BatchRenameService {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager; self.accessPolicy = accessPolicy
    }

    func plan(_ request: BatchRenameRequest) throws -> BatchRenamePlan {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        guard request.sources.count == request.proposedNames.count else { throw BatchRenameError.countMismatch }
        let sources = request.sources.map { $0.standardizedFileURL }
        let sourceSet = Set(sources)
        guard sourceSet.count == sources.count else { throw BatchRenameError.duplicateSource(sources[0]) }
        guard let directory = sources.first?.deletingLastPathComponent(), sources.allSatisfy({ $0.deletingLastPathComponent() == directory }) else {
            throw BatchRenameError.differentDirectories
        }
        try accessPolicy.validateAccess(to: directory)
        var destinations = Set<String>()
        var items: [BatchRenameItem] = []
        for (source, rawName) in zip(sources, request.proposedNames) {
            guard fileManager.fileExists(atPath: source.path) else { throw FileOperationError.sourceMissing(source) }
            let name = try FileNameValidator.validateSyntax(rawName)
            let destination = directory.appendingPathComponent(name).standardizedFileURL
            try accessPolicy.validateDestinationAccess(to: destination)
            let destinationKey = destination.path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard destinations.insert(destinationKey).inserted else { throw BatchRenameError.duplicateDestination(destination) }
            if fileManager.fileExists(atPath: destination.path), !sourceSet.contains(destination) {
                throw BatchRenameError.destinationCollision(destination)
            }
            items.append(.init(sourceURL: source, destinationURL: destination))
        }
        return BatchRenamePlan(items: items)
    }

    func execute(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler? = nil) async -> FileOperationResult {
        if Task.isCancelled { return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true) }
        let changing = plan.items.filter { $0.sourceURL != $0.destinationURL }
        guard !changing.isEmpty else { return .init(completedItems: plan.items.map(\.destinationURL), skippedItems: [], failedItems: [], wasCancelled: false) }
        let directory = changing[0].sourceURL.deletingLastPathComponent()
        var staged: [(item: BatchRenameItem, temporary: URL)] = []
        var completed: [URL] = []
        var warnings: [FileOperationCleanupWarning] = []
        do {
            return try await accessPolicy.withAccess(to: changing.flatMap { [$0.sourceURL, $0.destinationURL] }) {
                for (index, item) in changing.enumerated() {
                    try Task.checkCancellation()
                    var temporary: URL
                    repeat { temporary = directory.appendingPathComponent(".pulsefiles-batch-\(UUID().uuidString)") }
                    while self.fileManager.fileExists(atPath: temporary.path)
                    try self.fileManager.moveItem(at: item.sourceURL, to: temporary)
                    staged.append((item, temporary))
                    await progressHandler?(.init(currentItemName: item.sourceURL.lastPathComponent, completedCount: index, totalCount: changing.count * 2))
                }
                for (index, entry) in staged.enumerated() {
                    try Task.checkCancellation()
                    try self.fileManager.moveItem(at: entry.temporary, to: entry.item.destinationURL)
                    completed.append(entry.item.destinationURL)
                    await progressHandler?(.init(currentItemName: entry.item.destinationURL.lastPathComponent, completedCount: changing.count + index + 1, totalCount: changing.count * 2))
                }
                return .init(completedItems: completed, skippedItems: [], failedItems: [], wasCancelled: false)
            }
        } catch {
            for entry in staged.reversed() {
                let current = fileManager.fileExists(atPath: entry.temporary.path) ? entry.temporary : entry.item.destinationURL
                guard fileManager.fileExists(atPath: current.path) else { continue }
                do { try fileManager.moveItem(at: current, to: entry.item.sourceURL) }
                catch { warnings.append(.init(url: current, message: error.localizedDescription)) }
            }
            return .init(completedItems: completed, skippedItems: [], failedItems: warnings.isEmpty ? [] : [.init(url: directory, error: error)], cleanupWarnings: warnings, wasCancelled: error is CancellationError)
        }
    }
}

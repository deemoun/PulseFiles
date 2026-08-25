import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum BatchRenameError: LocalizedError, Equatable {
    case countMismatch
    case differentDirectories
    case duplicateSource(URL)
    case duplicateDestination(URL)
    case destinationCollision(URL)

    package var errorDescription: String? {
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
package final class BatchRenameService {
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let mutations: FileMutationEngine

    package init(fileManager: FileOperationFileManaging = FileManager.default, accessPolicy: SandboxFileAccessPolicy = .current,
                 pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationPreflightValidator.defaultPathSafetyState,
                 stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry(), mutations: FileMutationEngine? = nil) {
        self.fileManager = fileManager; self.accessPolicy = accessPolicy
        let descriptor = DescriptorRelativeFileOperator(fileManager: fileManager)
        let validator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy,
                                                        pathSafetyStateProvider: pathSafetyStateProvider)
        self.mutations = mutations ?? validator.mutationEngine(fileManager: fileManager, accessPolicy: accessPolicy,
                                                               descriptorOperator: descriptor, stagingRegistry: stagingRegistry)
    }

    package func plan(_ request: BatchRenameRequest) throws -> BatchRenamePlan {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        guard request.sources.count == request.proposedNames.count else { throw BatchRenameError.countMismatch }
        let sources = request.sources.map { $0.standardizedFileURL }
        let sourceSet = Set(sources)
        guard sourceSet.count == sources.count else { throw BatchRenameError.duplicateSource(sources[0]) }
        guard let directory = sources.first?.deletingLastPathComponent(), sources.allSatisfy({ $0.deletingLastPathComponent() == directory }) else {
            throw BatchRenameError.differentDirectories
        }
        try mutations.validateMutationDirectory(directory)
        var destinations = Set<String>()
        var items: [BatchRenameItem] = []
        for (source, rawName) in zip(sources, request.proposedNames) {
            try mutations.validateReadableSource(source)
            let name = try FileNameValidator.validateSyntax(rawName)
            let destination = directory.appendingPathComponent(name).standardizedFileURL
            try mutations.validateDestination(destination)
            let destinationKey = destination.path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard destinations.insert(destinationKey).inserted else { throw BatchRenameError.duplicateDestination(destination) }
            if fileManager.fileExists(atPath: destination.path), !sourceSet.contains(destination) {
                throw BatchRenameError.destinationCollision(destination)
            }
            items.append(.init(sourceURL: source, destinationURL: destination))
        }
        return BatchRenamePlan(items: items)
    }

    package func execute(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler? = nil) async -> FileOperationResult {
        if Task.isCancelled { return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true) }
        let changing = plan.items.filter { $0.sourceURL != $0.destinationURL }
        guard !changing.isEmpty else { return .init(completedItems: plan.items.map(\.destinationURL), skippedItems: [], failedItems: [], wasCancelled: false) }
        let directory = changing[0].sourceURL.deletingLastPathComponent()
        var staging: FileMutationEngine.StagingArea?
        var staged: [(item: BatchRenameItem, temporary: URL)] = []
        var completed: [URL] = []
        var warnings: [FileOperationCleanupWarning] = []
        do {
            return try await accessPolicy.withAccess(to: changing.flatMap { [$0.sourceURL, $0.destinationURL] }) {
                let owned = try self.mutations.makeStagingArea(in: directory, prefix: "batch")
                staging = owned
                for (index, item) in changing.enumerated() {
                    try Task.checkCancellation()
                    try self.mutations.validateReadableSource(item.sourceURL)
                    let temporary = owned.directory.appendingPathComponent(UUID().uuidString)
                    try self.mutations.rename(item.sourceURL, to: temporary)
                    staged.append((item, temporary))
                    await progressHandler?(.init(currentItemName: item.sourceURL.lastPathComponent, completedCount: index, totalCount: changing.count * 2))
                }
                for (index, entry) in staged.enumerated() {
                    try Task.checkCancellation()
                    try self.mutations.rename(entry.temporary, to: entry.item.destinationURL)
                    completed.append(entry.item.destinationURL)
                    await progressHandler?(.init(currentItemName: entry.item.destinationURL.lastPathComponent, completedCount: changing.count + index + 1, totalCount: changing.count * 2))
                }
                let cleanup = self.mutations.cleanup(owned)
                return .init(completedItems: completed, skippedItems: [], failedItems: [], cleanupWarnings: cleanup, wasCancelled: false)
            }
        } catch {
            for entry in staged.reversed() {
                let current = fileManager.fileExists(atPath: entry.temporary.path) ? entry.temporary : entry.item.destinationURL
                guard fileManager.fileExists(atPath: current.path) else { continue }
                do {
                    try mutations.rename(current, to: entry.item.sourceURL)
                    completed.removeAll { $0.standardizedFileURL == entry.item.destinationURL.standardizedFileURL }
                }
                catch { warnings.append(.init(url: current, message: error.localizedDescription)) }
            }
            if warnings.isEmpty, let staging { warnings.append(contentsOf: mutations.cleanup(staging)) }
            let failures: [FileOperationItemFailure] = error is CancellationError && warnings.isEmpty
                ? [] : [.init(url: directory, error: error)]
            return .init(completedItems: completed, skippedItems: [], failedItems: failures,
                         cleanupWarnings: warnings, wasCancelled: error is CancellationError)
        }
    }
}

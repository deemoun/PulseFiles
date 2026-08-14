import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

/// State shared by the operation coordinator and its blocking filesystem
/// worker. It intentionally records facts rather than attempting to interrupt
/// FileManager: many network and provider-backed calls are uninterruptible.
package final class FileOperationContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCurrentItem: URL?
    private var storedLastProgressDate = Date()
    private var storedIsAbandoned = false

    package func beginBlockingCall(for item: URL) {
        lock.lock(); defer { lock.unlock() }
        storedCurrentItem = item
    }

    package func recordProgress() {
        lock.lock(); defer { lock.unlock() }
        storedLastProgressDate = Date()
    }

    package func abandon() {
        lock.lock(); defer { lock.unlock() }
        storedIsAbandoned = true
    }

    package var needsVerification: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsAbandoned
    }

    package var currentItem: URL? { lock.lock(); defer { lock.unlock() }; return storedCurrentItem }
    package var lastProgressDate: Date { lock.lock(); defer { lock.unlock() }; return storedLastProgressDate }
}

package typealias FileOperationProgressHandler = @MainActor (FileOperationProgress) -> Void
package typealias FileConflictHandler = (URL) async -> FileConflictResolution

/// Requests a local copy of a provider-backed placeholder. `false` retains the
/// normal safe failure path when a provider cannot perform the download.
/// Uses macOS ubiquitous-item support and bounds waiting for an unavailable
/// provider so file operations never mutate an item that remains a placeholder.
package final class MacOSCloudDownloadPreparer: FileOperationCloudDownloadPreparing, @unchecked Sendable {
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval

    package init(timeout: TimeInterval = 30, pollInterval: TimeInterval = 0.25) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    package func prepareDownload(for url: URL) async throws -> Bool {
        #if os(macOS)
        guard (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true else { return false }
        guard (try? FileManager.default.startDownloadingUbiquitousItem(at: url)) != nil else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus == .current { return true }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return false
        #else
        return false
        #endif
    }
}

package final class FileOperationService: FileOperationServicing, FileOperationArchiveServicing, FileOperationBatchRenameServicing {
    /// Bounds traversal work independently of filesystem recursion so hostile
    /// or accidentally generated directory trees cannot exhaust the process.
    package struct TraversalLimits: Sendable {
        let maximumDepth: Int
        let maximumItems: Int

        init(maximumDepth: Int = 10_000, maximumItems: Int = 1_000_000) {
            self.maximumDepth = maximumDepth
            self.maximumItems = maximumItems
        }
    }

    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let destinationCapacityProvider: (URL) -> Int64?
    private let volumeIdentifierProvider: (URL) -> String?
    private let pathSafetyStateProvider: (URL) -> FileOperationPathSafetyState
    private let cloudDownloadPreparer: any FileOperationCloudDownloadPreparing
    private let descriptorOperator: DescriptorRelativeFileOperator
    private let preflightValidator: FileOperationPreflightValidator
    private let transferPlanner: FileTransferPlanner
    private let transferExecutor: FileTransferExecutor
    private let archiveAdapter: FileOperationArchiveAdapter
    private let batchRenameAdapter: FileOperationBatchRenameAdapter
    private let undoPlanBuilder = FileOperationUndoPlanBuilder()

    package init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationPreflightValidator.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationPreflightValidator.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationPreflightValidator.defaultPathSafetyState, cloudDownloadPreparer: any FileOperationCloudDownloadPreparing = MacOSCloudDownloadPreparer(), traversalLimits: TraversalLimits = .init(), replacementDirectoryProvider: @escaping (URL) throws -> URL = FileTransferExecutor.systemReplacementDirectory, stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.cloudDownloadPreparer = cloudDownloadPreparer
        let descriptorOperator = DescriptorRelativeFileOperator(fileManager: fileManager)
        let preflightValidator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider)
        let metadataPreserver = FileMetadataPreserver(fileManager: fileManager)
        self.descriptorOperator = descriptorOperator
        self.preflightValidator = preflightValidator
        self.transferPlanner = FileTransferPlanner(fileManager: fileManager, accessPolicy: accessPolicy)
        self.transferExecutor = FileTransferExecutor(fileManager: fileManager, streamingCopier: streamingCopier, descriptorOperator: descriptorOperator, preflightValidator: preflightValidator, metadataPreserver: metadataPreserver, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider, traversalLimits: traversalLimits, replacementDirectoryProvider: replacementDirectoryProvider, stagingRegistry: stagingRegistry)
        self.archiveAdapter = FileOperationArchiveAdapter(accessPolicy: accessPolicy)
        self.batchRenameAdapter = FileOperationBatchRenameAdapter(accessPolicy: accessPolicy)
    }

    package init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationPreflightValidator.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationPreflightValidator.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationPreflightValidator.defaultPathSafetyState, cloudDownloadPreparer: any FileOperationCloudDownloadPreparing = MacOSCloudDownloadPreparer(), traversalLimits: TraversalLimits = .init(), replacementDirectoryProvider: @escaping (URL) throws -> URL = FileTransferExecutor.systemReplacementDirectory, stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.cloudDownloadPreparer = cloudDownloadPreparer
        let descriptorOperator = DescriptorRelativeFileOperator(fileManager: fileManager)
        let preflightValidator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider)
        let metadataPreserver = FileMetadataPreserver(fileManager: fileManager)
        self.descriptorOperator = descriptorOperator
        self.preflightValidator = preflightValidator
        self.transferPlanner = FileTransferPlanner(fileManager: fileManager, accessPolicy: accessPolicy)
        self.transferExecutor = FileTransferExecutor(fileManager: fileManager, streamingCopier: streamingCopier, descriptorOperator: descriptorOperator, preflightValidator: preflightValidator, metadataPreserver: metadataPreserver, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider, traversalLimits: traversalLimits, replacementDirectoryProvider: replacementDirectoryProvider, stagingRegistry: stagingRegistry)
        self.archiveAdapter = FileOperationArchiveAdapter(accessPolicy: accessPolicy)
        self.batchRenameAdapter = FileOperationBatchRenameAdapter(accessPolicy: accessPolicy)
    }

    package func createArchive(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult {
        try await archiveAdapter.createArchive(request, progressHandler: progressHandler)
    }

    package func extractArchive(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult {
        try await archiveAdapter.extractArchive(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
    }

    package func planBatchRename(_ request: BatchRenameRequest) throws -> BatchRenamePlan {
        try batchRenameAdapter.planBatchRename(request)
    }

    package func batchRename(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler?) async -> FileOperationResult {
        await batchRenameAdapter.batchRename(plan, progressHandler: progressHandler)
    }

    package func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight {
        try preflightValidator.preflightTransferRequest(request, isMove: isMove)
        let hasReplacement = request.sources.contains { fileManager.fileExists(atPath: request.destinationDirectory.appendingPathComponent($0.lastPathComponent).path) }
        let requiresCopy = !isMove || hasReplacement || request.sources.contains { source in
            guard let sourceVolume = volumeIdentifierProvider(source), let destinationVolume = volumeIdentifierProvider(request.destinationDirectory) else { return true }
            return sourceVolume != destinationVolume
        }
        guard requiresCopy else { return .notRequired }
        let metadata: FileTransferExecutor.TransferMetadata?
        do {
            metadata = try await transferExecutor.calculateTransferMetadata(for: request.sources)
        } catch FileOperationError.traversalLimitExceeded {
            // The transfer path will report a traversal-limit failure against
            // the individual source rather than rejecting the whole request
            // from this optional capacity estimate.
            return .cannotVerify(required: nil)
        }
        guard let required = metadata?.byteCount else { return .cannotVerify(required: nil) }
        guard let available = destinationCapacityProvider(request.destinationDirectory) else { return .cannotVerify(required: required) }
        return available >= required ? .sufficient(required: required, available: available) : .insufficient(required: required, available: available)
    }

    private func enforceTransferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws {
        if case .insufficient(let required, let available) = try await transferCapacityPreflight(for: request, isMove: isMove) {
            throw FileOperationError.insufficientDestinationCapacity(required: required, available: available)
        }
    }

    package func copy(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        try await executeCancellableOperation(progressHandler: progressHandler) { context, progress in
            context.beginBlockingCall(for: request.sources.first ?? request.destinationDirectory)
            return try await self.copyOnWorker(request, conflictHandler: conflictHandler, progressHandler: progress)
        }
    }

    /// This runs the complete copy path on a detached executor. It deliberately
    /// includes preflight, recursive staging, placement, and FileManager calls;
    /// the only cross-executor work is the async conflict/progress callbacks.
    private func copyOnWorker(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Copy operation starting: sourceCount=\(request.sources.count); destination=\(DiagnosticLogger.sanitizedPath(request.destinationDirectory))")
        do {
            try await prepareCloudPlaceholders(for: request.sources, progressHandler: progressHandler)
            try preflightValidator.preflightTransferRequest(request)
            try await enforceTransferCapacityPreflight(for: request, isMove: false)
        } catch {
            logPreflightFailure(operation: "copy", error: error)
            throw error
        }
        let plans = try await transferPlanner.resolveTransferPlans(for: request, conflictHandler: conflictHandler) { destination, resolution in
            DiagnosticLogger.log(.info, category: "FileOperation", "Conflict decision: destination=\(DiagnosticLogger.sanitizedPath(destination)); resolution=\(resolution.logValue)")
        }
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            DiagnosticLogger.log(.info, category: "FileOperation", "Copy operation cancelled during conflict resolution: skippedCount=\(plans.filter { $0.conflictResolution == .skip }.count)")
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await accessPolicy.withAccess(to: request.sources + [request.destinationDirectory]) {
            let result = await transferExecutor.performTransfer(plans, kind: .copy, progressHandler: progressHandler)
            logCompletion(operation: "copy", result: result)
            return result
        }
    }

    package func move(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        try await executeCancellableOperation(progressHandler: progressHandler) { context, progress in
            context.beginBlockingCall(for: request.sources.first ?? request.destinationDirectory)
            return try await self.moveOnWorker(request, conflictHandler: conflictHandler, progressHandler: progress)
        }
    }

    /// Runs potentially blocking worker code with a context that survives task
    /// cancellation. The worker is retained by its Task until it exits; if a
    /// cancellation arrived while it was blocked, its eventual result is never
    /// represented as a safe completed/cancelled operation.
    private func executeCancellableOperation(
        progressHandler: FileOperationProgressHandler?,
        operation: @escaping @Sendable (FileOperationContext, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) async throws -> FileOperationResult {
        let context = FileOperationContext()
        let trackedProgress: FileOperationProgressHandler? = { progress in
            context.recordProgress()
            progressHandler?(progress)
        }
        let worker = Task.detached(priority: .utility) {
            let result = try await operation(context, trackedProgress)
            guard context.needsVerification else { return result }
            return FileOperationResult.unknownAfterAbandoning(currentItem: context.currentItem)
        }
        do {
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                context.abandon()
                worker.cancel()
            }
        } catch is CancellationError {
            return context.needsVerification
                ? .unknownAfterAbandoning(currentItem: context.currentItem)
                : FileOperationResult(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true)
        }
    }

    private func moveOnWorker(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Move operation starting: sourceCount=\(request.sources.count); destination=\(DiagnosticLogger.sanitizedPath(request.destinationDirectory))")
        do {
            try await prepareCloudPlaceholders(for: request.sources, progressHandler: progressHandler)
            try preflightValidator.preflightTransferRequest(request, isMove: true)
            try await enforceTransferCapacityPreflight(for: request, isMove: true)
        } catch {
            logPreflightFailure(operation: "move", error: error)
            throw error
        }
        let plans = try await transferPlanner.resolveTransferPlans(for: request, conflictHandler: conflictHandler) { destination, resolution in
            DiagnosticLogger.log(.info, category: "FileOperation", "Conflict decision: destination=\(DiagnosticLogger.sanitizedPath(destination)); resolution=\(resolution.logValue)")
        }
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await accessPolicy.withAccess(to: request.sources + [request.destinationDirectory]) {
            let result = await transferExecutor.performTransfer(plans, kind: .move, progressHandler: progressHandler)
            logCompletion(operation: "move", result: result)
            return result
        }
    }

    package func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try await prepareCloudPlaceholders(for: [source], progressHandler: progressHandler)
        let parentDirectory = source.deletingLastPathComponent()
        try preflightValidator.validateExistingSource(source)
        try preflightValidator.validateSourceAccess(source)
        try accessPolicy.validateAccess(to: parentDirectory)
        try preflightValidator.validateExistingDirectory(parentDirectory)

        let destinationName = try FileNameValidator.validate(rawName, in: parentDirectory, replacing: source)
        let destination = parentDirectory.appendingPathComponent(destinationName)

        do {
            try preflightValidator.preflightRename(source: source, destination: destination)
        } catch {
            logPreflightFailure(operation: "rename", error: error)
            throw error
        }
        DiagnosticLogger.log(.info, category: "FileOperation", "Rename operation starting: source=\(DiagnosticLogger.sanitizedPath(source)); destination=\(DiagnosticLogger.sanitizedPath(destination))")
        await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: 0, totalCount: 1))

        do {
            try accessPolicy.withAccess(to: [source, parentDirectory]) {
                try descriptorOperator.rename(source, to: destination)
            }
            await progressHandler?(FileOperationProgress(currentItemName: destination.lastPathComponent, completedCount: 1, totalCount: 1))
            let result = FileOperationResult(completedItems: [destination], skippedItems: [], failedItems: [], wasCancelled: false, recovery: undoPlanBuilder.rename(from: source, to: destination))
            logCompletion(operation: "rename", result: result)
            return result
        } catch {
            await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: 1, totalCount: 1))
            let result = FileOperationResult(completedItems: [], skippedItems: [], failedItems: [FileOperationItemFailure(url: source, error: error)], wasCancelled: false)
            logCompletion(operation: "rename", result: result)
            return result
        }
    }

    package func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        guard recovery.eligibility() == .eligible else { throw FileOperationError.undoUnavailable }
        // Copies are only reversible by removing the exact destination that we
        // created. Never use the source as a precondition: it is expected to
        // remain after a copy.
        if recovery.kind == .copy {
            for item in recovery.items {
                guard let expectedIdentity = item.destinationIdentity,
                      preflightValidator.itemIdentity(at: item.destinationURL) == expectedIdentity else {
                    throw FileOperationError.undoUnavailable
                }
                try preflightValidator.validateExistingSource(item.destinationURL)
                try preflightValidator.validateAvailableSource(item.destinationURL)
                try preflightValidator.validateWritableMutationTarget(item.destinationURL.deletingLastPathComponent())
                try accessPolicy.validateAccess(to: item.destinationURL)
            }
            return await accessPolicy.withAccess(to: recovery.items.map(\.destinationURL)) {
                var completed: [URL] = []
                var failures: [FileOperationItemFailure] = []
                var wasCancelled = false
                for (index, item) in recovery.items.enumerated() {
                    if Task.isCancelled { wasCancelled = true; break }
                    await progressHandler?(FileOperationProgress(currentItemName: item.destinationURL.lastPathComponent, completedCount: index, totalCount: recovery.items.count))
                    // Recheck directly before removal to close the validation/mutation window.
                    do {
                        guard preflightValidator.itemIdentity(at: item.destinationURL) == item.destinationIdentity else { throw FileOperationError.undoUnavailable }
                        try descriptorOperator.remove(item.destinationURL)
                        completed.append(item.destinationURL)
                    } catch {
                        failures.append(.init(url: item.destinationURL, error: error))
                    }
                }
                return FileOperationResult(completedItems: completed, skippedItems: [], failedItems: failures, wasCancelled: wasCancelled)
            }
        }
        try await prepareCloudPlaceholders(for: recovery.items.map(\.destinationURL), progressHandler: progressHandler)
        for item in recovery.items {
            if recovery.kind == .trash,
               let expectedIdentity = item.destinationIdentity,
               preflightValidator.itemIdentity(at: item.destinationURL) != expectedIdentity {
                throw FileOperationError.undoUnavailable
            }
            try preflightValidator.validateExistingSource(item.destinationURL)
            try preflightValidator.validateAvailableSource(item.destinationURL)
            try preflightValidator.validateExistingDirectory(item.originalURL.deletingLastPathComponent())
            try preflightValidator.validateWritableMutationTarget(item.destinationURL.deletingLastPathComponent())
            try preflightValidator.validateWritableMutationTarget(item.originalURL.deletingLastPathComponent())
            try accessPolicy.validateAccess(to: item.destinationURL)
            try accessPolicy.validateDestinationAccess(to: item.originalURL)
            if fileManager.fileExists(atPath: item.originalURL.path) { throw FileOperationError.destinationExists(item.originalURL) }
        }
        return await accessPolicy.withAccess(to: recovery.items.flatMap { [$0.destinationURL, $0.originalURL.deletingLastPathComponent()] }) {
            var completed: [URL] = []
            var failures: [FileOperationItemFailure] = []
            var wasCancelled = false
            for (index, item) in recovery.items.enumerated() {
                if Task.isCancelled { wasCancelled = true; break }
                await progressHandler?(FileOperationProgress(currentItemName: item.destinationURL.lastPathComponent, completedCount: index, totalCount: recovery.items.count))
                do {
                    if recovery.kind == .trash, preflightValidator.itemIdentity(at: item.destinationURL) != item.destinationIdentity { throw FileOperationError.undoUnavailable }
                    try descriptorOperator.rename(item.destinationURL, to: item.originalURL)
                    completed.append(item.originalURL)
                } catch {
                    failures.append(.init(url: item.destinationURL, error: error))
                }
            }
            return FileOperationResult(completedItems: completed, skippedItems: [], failedItems: failures, wasCancelled: wasCancelled)
        }
    }

    package func createFolder(named rawName: String, in directory: URL) async throws -> FileOperationResult {
        try await createItem(named: rawName, in: directory, isDirectory: true)
    }

    package func createFile(named rawName: String, in directory: URL) async throws -> FileOperationResult {
        try await createItem(named: rawName, in: directory, isDirectory: false)
    }

    /// Creation is a single blocking filesystem mutation, but its validation
    /// and collision check can also be slow on provider-backed directories.
    /// Keep all of it on a utility executor and report cancellation without
    /// pretending that an already-started FileManager call was interrupted.
    private func createItem(named rawName: String, in directory: URL, isDirectory: Bool) async throws -> FileOperationResult {
        let context = FileOperationContext()
        let operationName = isDirectory ? "folder" : "file"
        let worker = Task.detached(priority: .utility) { [self] () throws -> FileOperationResult in
            try Task.checkCancellation()
            let destination = try preflightValidator.preflightCreation(rawName: rawName, in: directory, isDirectory: isDirectory)
            DiagnosticLogger.log(.info, category: "FileOperation", "Create \(operationName) operation starting: destination=\(DiagnosticLogger.sanitizedPath(destination))")
            try Task.checkCancellation()
            context.beginBlockingCall(for: destination)
            do {
                try accessPolicy.withAccess(to: [directory]) {
                    try descriptorOperator.create(destination, isDirectory: isDirectory)
                }
            } catch {
                DiagnosticLogger.log(.error, category: "FileOperation", "Create \(operationName) operation failed: destination=\(DiagnosticLogger.sanitizedPath(destination)); reason=\(error.localizedDescription)")
                throw error
            }
            if context.needsVerification {
                return FileOperationResult.unknownAfterAbandoning(currentItem: destination)
            }
            return FileOperationResult(completedItems: [destination], skippedItems: [], failedItems: [], wasCancelled: false)
        }
        do {
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                context.abandon()
                worker.cancel()
            }
        } catch is CancellationError {
            return FileOperationResult(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true)
        }
    }

    package func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Trash operation starting: itemCount=\(urls.count)")
        try await prepareCloudPlaceholders(for: urls, progressHandler: progressHandler)
        do { try preflightValidator.preflightDelete(urls) } catch { logPreflightFailure(operation: "trash", error: error); throw error }
        var trashedItems: [FileOperationRecovery.Item] = []
        let result = await accessPolicy.withAccess(to: urls) {
            await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
                #if os(macOS)
                // NSFileManager has no trashat equivalent. Pin and verify the
                // parent and final component before invoking its platform trash API.
                try descriptorOperator.verifyExistingItem(url)
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                guard let resultingURL else { throw FileOperationError.undoUnavailable }
                let trashURL = resultingURL as URL
                guard let identity = preflightValidator.itemIdentity(at: trashURL) else { throw FileOperationError.undoUnavailable }
                trashedItems.append(.init(originalURL: url, destinationURL: trashURL, destinationIdentity: identity))
                #else
                throw CocoaError(.featureUnsupported)
                #endif
            }
        }
        let trashRecovery = result.succeededCompletely ? undoPlanBuilder.trash(trashedItems, expectedCount: urls.count) : nil
        let recoverableResult = trashRecovery != nil
            ? FileOperationResult(completedItems: result.completedItems, skippedItems: result.skippedItems, failedItems: result.failedItems, cleanupWarnings: result.cleanupWarnings, wasCancelled: result.wasCancelled, needsVerification: result.needsVerification, recovery: trashRecovery)
            : result
        logCompletion(operation: "trash", result: recoverableResult)
        return recoverableResult
    }

    package func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation starting: itemCount=\(urls.count)")
        try await prepareCloudPlaceholders(for: urls, progressHandler: progressHandler)
        do { try preflightValidator.preflightDelete(urls) } catch { logPreflightFailure(operation: "delete", error: error); throw error }
        let result = await accessPolicy.withAccess(to: urls) {
            await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
                try descriptorOperator.remove(url)
            }
        }
        logCompletion(operation: "delete", result: result)
        return result
    }

    private func performDelete(
        _ urls: [URL],
        progressHandler: FileOperationProgressHandler?,
        operation: (FileOperationFileManaging, URL) throws -> Void
    ) async -> FileOperationResult {
        await FileOperationTrashDeleteExecutor(fileManager: fileManager).execute(
            urls,
            progressHandler: progressHandler,
            validate: { url in
                try preflightValidator.validateAvailableSource(url)
                try preflightValidator.validateWritableMutationTarget(url.deletingLastPathComponent())
            },
            shouldStopAfterError: isUnavailableVolumeError,
            operation: operation
        )
    }

    /// Directory enumeration and metadata reads can be expensive (and can
    /// block on network volumes), so plan them off the caller's actor.

    package static func keepBothDestination(
        for destination: URL,
        reservedDestinations: Set<String> = [],
        fileExists: (URL) -> Bool
    ) -> URL {
        FileTransferPlanner.keepBothDestination(
            for: destination,
            reservedDestinations: reservedDestinations,
            fileExists: fileExists
        )
    }

    /// Access is checked before the provider request and revalidated once it
    /// reports success, preventing a download race from bypassing safety rules.
    private func prepareCloudPlaceholders(for urls: [URL], progressHandler: FileOperationProgressHandler?) async throws {
        for (index, url) in urls.enumerated() where pathSafetyStateProvider(url).isICloudPlaceholder {
            try preflightValidator.validateExistingSource(url)
            try preflightValidator.validateAvailableSource(url, allowingPlaceholder: true)
            try preflightValidator.validateSourceAccess(url)
            await progressHandler?(FileOperationProgress(currentItemName: "Downloading %@".localized(with: url.lastPathComponent), completedCount: index, totalCount: urls.count, isPreparingTransfer: true))
            guard try await cloudDownloadPreparer.prepareDownload(for: url) else {
                throw FileOperationError.iCloudItemNotDownloaded(url)
            }
            try Task.checkCancellation()
            try preflightValidator.validateExistingSource(url)
            try preflightValidator.validateAvailableSource(url)
            try preflightValidator.validateSourceAccess(url)
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: index + 1, totalCount: urls.count, isPreparingTransfer: true))
        }
    }

    /// Reject a parent and one of its descendants in the same request. This is
    /// intentionally shared by copy, move, trash, and permanent delete so the
    /// outcome cannot depend on selection order or mutation progress.

    private func logPreflightFailure(operation: String, error: Error) {
        DiagnosticLogger.log(.warning, category: "FileOperation", "Preflight failed: operation=\(operation); reason=\(error.localizedDescription)")
    }

    private func logCompletion(operation: String, result: FileOperationResult) {
        let level: DiagnosticLogLevel = result.succeededCompletely ? .info : (result.wasCancelled ? .warning : .error)
        DiagnosticLogger.log(level, category: "FileOperation", "Operation completed: operation=\(operation); completed=\(result.completedItems.count); skipped=\(result.skippedItems.count); failed=\(result.failedItems.count); cleanupWarnings=\(result.cleanupWarnings.count); cancelled=\(result.wasCancelled)")
        for warning in result.cleanupWarnings {
            DiagnosticLogger.log(.warning, category: "FileOperation", "Cleanup warning: path=\(DiagnosticLogger.sanitizedPath(warning.url)); reason=\(warning.message)")
        }
        for failure in result.failedItems {
            DiagnosticLogger.log(.error, category: "FileOperation", "Partial failure: path=\(DiagnosticLogger.sanitizedPath(failure.url)); reason=\(failure.error.localizedDescription)")
        }
    }

}


private extension FileConflictResolution {
    package var logValue: String {
        switch self {
        case .replace: return "replace"
        case .skip: return "skip"
        case .keepBoth: return "keepBoth"
        case .cancel: return "cancel"
        case .applyToRemainingReplace: return "replace (remaining)"
        case .applyToRemainingSkip: return "skip (remaining)"
        case .applyToRemainingKeepBoth: return "keepBoth (remaining)"
        }
    }
}

import Foundation
#if os(macOS)
import Darwin
#endif

/// State shared by the operation coordinator and its blocking filesystem
/// worker. It intentionally records facts rather than attempting to interrupt
/// FileManager: many network and provider-backed calls are uninterruptible.
final class FileOperationContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCurrentItem: URL?
    private var storedLastProgressDate = Date()
    private var storedIsAbandoned = false

    func beginBlockingCall(for item: URL) {
        lock.lock(); defer { lock.unlock() }
        storedCurrentItem = item
    }

    func recordProgress() {
        lock.lock(); defer { lock.unlock() }
        storedLastProgressDate = Date()
    }

    func abandon() {
        lock.lock(); defer { lock.unlock() }
        storedIsAbandoned = true
    }

    var needsVerification: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsAbandoned
    }

    var currentItem: URL? { lock.lock(); defer { lock.unlock() }; return storedCurrentItem }
    var lastProgressDate: Date { lock.lock(); defer { lock.unlock() }; return storedLastProgressDate }
}

typealias FileOperationProgressHandler = @MainActor (FileOperationProgress) -> Void
typealias FileConflictHandler = (URL) async -> FileConflictResolution

/// Requests a local copy of a provider-backed placeholder. `false` retains the
/// normal safe failure path when a provider cannot perform the download.
/// Uses macOS ubiquitous-item support and bounds waiting for an unavailable
/// provider so file operations never mutate an item that remains a placeholder.
final class MacOSCloudDownloadPreparer: FileOperationCloudDownloadPreparing, @unchecked Sendable {
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval

    init(timeout: TimeInterval = 30, pollInterval: TimeInterval = 0.25) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    func prepareDownload(for url: URL) async throws -> Bool {
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

final class FileOperationService: FileOperationServicing, FileOperationArchiveServicing, FileOperationBatchRenameServicing {
    /// PulseFiles copies symbolic links as links, never as the item they point
    /// to. This avoids unintentionally reading content outside the selected
    /// tree, prevents directory-link cycles, and preserves the user's link.
    /// Link traversal is deliberately not a transfer mode; any future mode
    /// that follows links must validate each resolved descendant with
    /// `SandboxFileAccessPolicy` and detect repeated file identities/paths.
    private enum SourceItemKind {
        case file
        case directory
        case symbolicLink(destination: String)
        /// An opaque Finder alias. It is copied as an object, never resolved.
        case finderAlias
    }

    private struct TransferFailure: Error {
        let underlyingError: Error
        let cleanupWarnings: [FileOperationCleanupWarning]
    }

    private enum TransferKind {
        case copy
        case move
    }

    private struct TransferPlan {
        let source: URL
        let destination: URL
        let conflictResolution: FileConflictResolution
        let replacesExistingDestination: Bool
    }

    private struct TransferMetadata: Sendable {
        let itemCount: Int
        let byteCount: Int64?
    }

    /// A system-managed, same-volume directory used for one transfer. The
    /// marker is deliberately stored inside the directory: no implementation
    /// detail or partial item is published beside the user's destination.
    private struct StagingArea {
        let operationID: UUID
        let directory: URL
        let marker: URL
        let stagedItem: URL
        let backupItem: URL

        func isOwned(using fileManager: FileOperationFileManaging) -> Bool {
            fileManager.fileExists(atPath: marker.path)
        }
    }

    /// Bounds traversal work independently of filesystem recursion so hostile
    /// or accidentally generated directory trees cannot exhaust the process.
    struct TraversalLimits: Sendable {
        let maximumDepth: Int
        let maximumItems: Int

        init(maximumDepth: Int = 10_000, maximumItems: Int = 1_000_000) {
            self.maximumDepth = maximumDepth
            self.maximumItems = maximumItems
        }
    }

    private final class RecursiveProgressState {
        /// Progress is rendered on the main actor.  A copy can produce an
        /// update for every byte chunk (and every item in a large folder), so
        /// publishing each one can starve unrelated windows of event-loop
        /// time.  Keep the most recent state and publish at a display-friendly
        /// cadence instead.
        private static let minimumUpdateInterval: TimeInterval = 1.0 / 15.0

        let totalItemCount: Int?
        var completedItemCount: Int
        let totalByteCount: Int64?
        var completedByteCount: Int64
        private var lastProgressUpdate = Date.distantPast

        init(
            totalItemCount: Int?,
            completedItemCount: Int,
            totalByteCount: Int64?,
            completedByteCount: Int64
        ) {
            self.totalItemCount = totalItemCount
            self.completedItemCount = completedItemCount
            self.totalByteCount = totalByteCount
            self.completedByteCount = completedByteCount
        }

        func shouldPublishProgress(force: Bool) -> Bool {
            let now = Date()
            guard force || now.timeIntervalSince(lastProgressUpdate) >= Self.minimumUpdateInterval else {
                return false
            }
            lastProgressUpdate = now
            return true
        }
    }

    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let streamingCopier: FileOperationStreamingCopying
    private let destinationCapacityProvider: (URL) -> Int64?
    private let volumeIdentifierProvider: (URL) -> String?
    private let pathSafetyStateProvider: (URL) -> FileOperationPathSafetyState
    private let cloudDownloadPreparer: any FileOperationCloudDownloadPreparing
    private let traversalLimits: TraversalLimits
    private let replacementDirectoryProvider: (URL) throws -> URL
    private let stagingRegistry: StagingOwnershipRegistry
    private let descriptorOperator: DescriptorRelativeFileOperator
    private let preflightValidator: FileOperationPreflightValidator
    private let transferPlanner: FileTransferPlanner
    private let transferExecutor: FileTransferExecutor
    private let metadataPreserver: FileMetadataPreserver
    private let archiveAdapter: FileOperationArchiveAdapter
    private let batchRenameAdapter: FileOperationBatchRenameAdapter
    private let undoPlanBuilder = FileOperationUndoPlanBuilder()

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationService.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationService.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationService.defaultPathSafetyState, cloudDownloadPreparer: any FileOperationCloudDownloadPreparing = MacOSCloudDownloadPreparer(), traversalLimits: TraversalLimits = .init(), replacementDirectoryProvider: @escaping (URL) throws -> URL = FileOperationService.systemReplacementDirectory, stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.streamingCopier = streamingCopier
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.cloudDownloadPreparer = cloudDownloadPreparer
        self.traversalLimits = traversalLimits
        self.replacementDirectoryProvider = replacementDirectoryProvider
        self.stagingRegistry = stagingRegistry
        self.descriptorOperator = DescriptorRelativeFileOperator(fileManager: fileManager)
        self.preflightValidator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider)
        self.transferPlanner = FileTransferPlanner(fileManager: fileManager, accessPolicy: accessPolicy)
        self.transferExecutor = FileTransferExecutor(fileManager: fileManager, streamingCopier: streamingCopier, descriptorOperator: descriptorOperator)
        self.metadataPreserver = FileMetadataPreserver(fileManager: fileManager)
        self.archiveAdapter = FileOperationArchiveAdapter(accessPolicy: accessPolicy)
        self.batchRenameAdapter = FileOperationBatchRenameAdapter(accessPolicy: accessPolicy)
    }

    init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationService.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationService.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationService.defaultPathSafetyState, cloudDownloadPreparer: any FileOperationCloudDownloadPreparing = MacOSCloudDownloadPreparer(), traversalLimits: TraversalLimits = .init(), replacementDirectoryProvider: @escaping (URL) throws -> URL = FileOperationService.systemReplacementDirectory, stagingRegistry: StagingOwnershipRegistry = StagingOwnershipRegistry()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.streamingCopier = streamingCopier
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.cloudDownloadPreparer = cloudDownloadPreparer
        self.traversalLimits = traversalLimits
        self.replacementDirectoryProvider = replacementDirectoryProvider
        self.stagingRegistry = stagingRegistry
        self.descriptorOperator = DescriptorRelativeFileOperator(fileManager: fileManager)
        self.preflightValidator = FileOperationPreflightValidator(fileManager: fileManager, accessPolicy: accessPolicy, pathSafetyStateProvider: pathSafetyStateProvider)
        self.transferPlanner = FileTransferPlanner(fileManager: fileManager, accessPolicy: accessPolicy)
        self.transferExecutor = FileTransferExecutor(fileManager: fileManager, streamingCopier: streamingCopier, descriptorOperator: descriptorOperator)
        self.metadataPreserver = FileMetadataPreserver(fileManager: fileManager)
        self.archiveAdapter = FileOperationArchiveAdapter(accessPolicy: accessPolicy)
        self.batchRenameAdapter = FileOperationBatchRenameAdapter(accessPolicy: accessPolicy)
    }

    static func systemReplacementDirectory(appropriateFor destination: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
    }

    func createArchive(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult {
        try await archiveAdapter.createArchive(request, progressHandler: progressHandler)
    }

    func extractArchive(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult {
        try await archiveAdapter.extractArchive(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
    }

    func planBatchRename(_ request: BatchRenameRequest) throws -> BatchRenamePlan {
        try batchRenameAdapter.planBatchRename(request)
    }

    func batchRename(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler?) async -> FileOperationResult {
        await batchRenameAdapter.batchRename(plan, progressHandler: progressHandler)
    }

    func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight {
        try preflightTransferRequest(request, isMove: isMove)
        let hasReplacement = request.sources.contains { fileManager.fileExists(atPath: request.destinationDirectory.appendingPathComponent($0.lastPathComponent).path) }
        let requiresCopy = !isMove || hasReplacement || request.sources.contains { source in
            guard let sourceVolume = volumeIdentifierProvider(source), let destinationVolume = volumeIdentifierProvider(request.destinationDirectory) else { return true }
            return sourceVolume != destinationVolume
        }
        guard requiresCopy else { return .notRequired }
        let metadata: TransferMetadata?
        do {
            metadata = try await calculateTransferMetadata(for: request.sources)
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

    private static func defaultDestinationCapacity(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
    }

    private static func defaultVolumeIdentifier(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey]), let identifier = values.volumeIdentifier else { return nil }
        if let identifier = identifier as? UUID {
            return identifier.uuidString
        }
        return String(describing: identifier)
    }

    private static func defaultPathSafetyState(for url: URL) -> FileOperationPathSafetyState {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey, .isAliasFileKey]) else {
            return FileOperationPathSafetyState(isAvailable: false)
        }
        return FileOperationPathSafetyState(
            isAvailable: true,
            isReadOnlyVolume: values.volumeIsReadOnly == true,
            isICloudPlaceholder: values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current,
            isFinderAlias: values.isAliasFile == true
        )
    }

    func copy(
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
            try preflightTransferRequest(request)
            try await enforceTransferCapacityPreflight(for: request, isMove: false)
        } catch {
            logPreflightFailure(operation: "copy", error: error)
            throw error
        }
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            DiagnosticLogger.log(.info, category: "FileOperation", "Copy operation cancelled during conflict resolution: skippedCount=\(plans.filter { $0.conflictResolution == .skip }.count)")
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await accessPolicy.withAccess(to: request.sources + [request.destinationDirectory]) {
            let result = await performTransfer(plans, kind: .copy, progressHandler: progressHandler)
            logCompletion(operation: "copy", result: result)
            return result
        }
    }

    func move(
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
            try preflightTransferRequest(request, isMove: true)
            try await enforceTransferCapacityPreflight(for: request, isMove: true)
        } catch {
            logPreflightFailure(operation: "move", error: error)
            throw error
        }
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await accessPolicy.withAccess(to: request.sources + [request.destinationDirectory]) {
            let result = await performTransfer(plans, kind: .move, progressHandler: progressHandler)
            logCompletion(operation: "move", result: result)
            return result
        }
    }

    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try await prepareCloudPlaceholders(for: [source], progressHandler: progressHandler)
        let parentDirectory = source.deletingLastPathComponent()
        try validateExistingSource(source)
        try validateSourceAccess(source)
        try accessPolicy.validateAccess(to: parentDirectory)
        try validateExistingDirectory(parentDirectory)

        let destinationName = try FileNameValidator.validate(rawName, in: parentDirectory, replacing: source)
        let destination = parentDirectory.appendingPathComponent(destinationName)

        do {
            try preflightRename(source: source, destination: destination)
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

    func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        guard recovery.eligibility() == .eligible else { throw FileOperationError.undoUnavailable }
        // Copies are only reversible by removing the exact destination that we
        // created. Never use the source as a precondition: it is expected to
        // remain after a copy.
        if recovery.kind == .copy {
            for item in recovery.items {
                guard let expectedIdentity = item.destinationIdentity,
                      itemIdentity(at: item.destinationURL) == expectedIdentity else {
                    throw FileOperationError.undoUnavailable
                }
                try validateExistingSource(item.destinationURL)
                try validateAvailableSource(item.destinationURL)
                try validateWritableMutationTarget(item.destinationURL.deletingLastPathComponent())
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
                        guard itemIdentity(at: item.destinationURL) == item.destinationIdentity else { throw FileOperationError.undoUnavailable }
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
               itemIdentity(at: item.destinationURL) != expectedIdentity {
                throw FileOperationError.undoUnavailable
            }
            try validateExistingSource(item.destinationURL)
            try validateAvailableSource(item.destinationURL)
            try validateExistingDirectory(item.originalURL.deletingLastPathComponent())
            try validateWritableMutationTarget(item.destinationURL.deletingLastPathComponent())
            try validateWritableMutationTarget(item.originalURL.deletingLastPathComponent())
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
                    if recovery.kind == .trash, itemIdentity(at: item.destinationURL) != item.destinationIdentity { throw FileOperationError.undoUnavailable }
                    try descriptorOperator.rename(item.destinationURL, to: item.originalURL)
                    completed.append(item.originalURL)
                } catch {
                    failures.append(.init(url: item.destinationURL, error: error))
                }
            }
            return FileOperationResult(completedItems: completed, skippedItems: [], failedItems: failures, wasCancelled: wasCancelled)
        }
    }

    private func itemIdentity(at url: URL) -> String? {
        guard let identifier = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return nil }
        return String(describing: identifier)
    }

    func createFolder(named rawName: String, in directory: URL) async throws -> FileOperationResult {
        try await createItem(named: rawName, in: directory, isDirectory: true)
    }

    func createFile(named rawName: String, in directory: URL) async throws -> FileOperationResult {
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
            let destination = try preflightCreation(rawName: rawName, in: directory, isDirectory: isDirectory)
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

    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Trash operation starting: itemCount=\(urls.count)")
        try await prepareCloudPlaceholders(for: urls, progressHandler: progressHandler)
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "trash", error: error); throw error }
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
                guard let identity = itemIdentity(at: trashURL) else { throw FileOperationError.undoUnavailable }
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

    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation starting: itemCount=\(urls.count)")
        try await prepareCloudPlaceholders(for: urls, progressHandler: progressHandler)
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "delete", error: error); throw error }
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
                try validateAvailableSource(url)
                try validateWritableMutationTarget(url.deletingLastPathComponent())
            },
            shouldStopAfterError: isUnavailableVolumeError,
            operation: operation
        )
    }

    private func performTransfer(
        _ plans: [TransferPlan],
        kind: TransferKind,
        progressHandler: FileOperationProgressHandler?
    ) async -> FileOperationResult {
        var completedItems: [URL] = []
        var skippedItems: [URL] = []
        var failedItems: [FileOperationItemFailure] = []
        var cleanupWarnings: [FileOperationCleanupWarning] = []
        let activePlans = plans.filter { $0.conflictResolution.performsTransfer }
        let totalCount = activePlans.count
        var completedCount = 0
        if progressHandler != nil {
            await progressHandler?(FileOperationProgress(currentItemName: "Preparing transfer".localized, completedCount: 0, totalCount: totalCount, isPreparingTransfer: true))
        }
        let metadata: TransferMetadata?
        do {
            metadata = progressHandler == nil ? nil : try await calculateTransferMetadata(for: activePlans.map(\.source)) { scannedItemCount, currentItem in
                await progressHandler?(FileOperationProgress(
                    currentItemName: currentItem.lastPathComponent,
                    completedCount: 0,
                    totalCount: totalCount,
                    completedRecursiveItemCount: scannedItemCount,
                    totalRecursiveItemCount: nil,
                    isPreparingTransfer: true
                ))
            }
        } catch is CancellationError {
            return FileOperationResult(completedItems: completedItems, skippedItems: skippedItems, failedItems: failedItems, cleanupWarnings: cleanupWarnings, wasCancelled: true)
        } catch {
            metadata = nil
        }
        let recursiveProgress = RecursiveProgressState(
            totalItemCount: metadata?.itemCount,
            completedItemCount: 0,
            totalByteCount: metadata?.byteCount,
            completedByteCount: 0
        )

        skippedItems.append(contentsOf: plans.filter { $0.conflictResolution == .skip }.map(\.source))

        for plan in activePlans {
            if Task.isCancelled {
                DiagnosticLogger.log(.info, category: "FileOperation", "Transfer operation cancelled: completedCount=\(completedItems.count); skippedCount=\(skippedItems.count); failedCount=\(failedItems.count); cleanupWarningCount=\(cleanupWarnings.count)")
                return FileOperationResult(
                    completedItems: completedItems,
                    skippedItems: skippedItems,
                    failedItems: failedItems,
                    cleanupWarnings: cleanupWarnings,
                    wasCancelled: true
                )
            }

            await emitProgress(
                currentItem: plan.source,
                completedCount: completedCount,
                totalCount: totalCount,
                recursiveProgress: recursiveProgress,
                progressHandler: progressHandler
            )
            // A volume can disappear after preflight. Re-check immediately before
            // mutating and stop the request so later items are never touched.
            guard fileManager.fileExists(atPath: plan.source.path) else {
                failedItems.append(FileOperationItemFailure(url: plan.source, error: FileOperationError.sourceMissing(plan.source)))
                break
            }
            do {
                try validateAvailableSource(plan.source)
                try validateWritableMutationTarget(plan.destination.deletingLastPathComponent())
                if kind == .move {
                    try validateWritableMutationTarget(plan.source.deletingLastPathComponent())
                }
            } catch {
                failedItems.append(FileOperationItemFailure(url: plan.source, error: error))
                break
            }
            guard fileManager.fileExists(atPath: plan.destination.deletingLastPathComponent().path) else {
                failedItems.append(FileOperationItemFailure(url: plan.destination, error: FileOperationError.destinationDirectoryMissing(plan.destination.deletingLastPathComponent())))
                break
            }
            do {
                switch kind {
                case .copy:
                    let warnings = try await safelyCopy(
                        source: plan.source,
                        to: plan.destination,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        recursiveProgress: recursiveProgress,
                        progressHandler: progressHandler
                    )
                    cleanupWarnings.append(contentsOf: warnings)
                case .move:
                    let warnings = try await safelyMove(
                        source: plan.source,
                        to: plan.destination,
                        replacingExistingDestination: plan.replacesExistingDestination,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        recursiveProgress: recursiveProgress,
                        progressHandler: progressHandler
                    )
                    cleanupWarnings.append(contentsOf: warnings)
                }
                completedItems.append(plan.source)
            } catch let failure as TransferFailure where failure.underlyingError is CancellationError {
                cleanupWarnings.append(contentsOf: failure.cleanupWarnings)
                DiagnosticLogger.log(.info, category: "FileOperation", "Transfer operation cancelled by task check: completedCount=\(completedItems.count); skippedCount=\(skippedItems.count); failedCount=\(failedItems.count); cleanupWarningCount=\(cleanupWarnings.count)")
                return FileOperationResult(
                    completedItems: completedItems,
                    skippedItems: skippedItems,
                    failedItems: failedItems,
                    cleanupWarnings: cleanupWarnings,
                    wasCancelled: true
                )
            } catch let failure as TransferFailure {
                cleanupWarnings.append(contentsOf: failure.cleanupWarnings)
                DiagnosticLogger.log(.error, category: "FileOperation", "Transfer item failed: source=\(DiagnosticLogger.sanitizedPath(plan.source)); destination=\(DiagnosticLogger.sanitizedPath(plan.destination)); reason=\(failure.underlyingError.localizedDescription)")
                failedItems.append(FileOperationItemFailure(url: plan.source, error: failure.underlyingError))
                if isUnavailableVolumeError(failure.underlyingError) {
                    break
                }
            } catch is CancellationError {
                DiagnosticLogger.log(.info, category: "FileOperation", "Transfer operation cancelled by task check: completedCount=\(completedItems.count); skippedCount=\(skippedItems.count); failedCount=\(failedItems.count); cleanupWarningCount=\(cleanupWarnings.count)")
                return FileOperationResult(
                    completedItems: completedItems,
                    skippedItems: skippedItems,
                    failedItems: failedItems,
                    cleanupWarnings: cleanupWarnings,
                    wasCancelled: true
                )
            } catch {
                DiagnosticLogger.log(.error, category: "FileOperation", "Transfer item failed: source=\(DiagnosticLogger.sanitizedPath(plan.source)); destination=\(DiagnosticLogger.sanitizedPath(plan.destination)); reason=\(error.localizedDescription)")
                failedItems.append(FileOperationItemFailure(url: plan.source, error: error))
                if isUnavailableVolumeError(error) {
                    break
                }
            }
            completedCount += 1
            if recursiveProgress.totalItemCount == nil {
                recursiveProgress.completedItemCount = completedCount
            }
            await emitProgress(
                currentItem: plan.source,
                completedCount: completedCount,
                totalCount: totalCount,
                recursiveProgress: recursiveProgress,
                progressHandler: progressHandler
            )
        }

        let canRecover = skippedItems.isEmpty && failedItems.isEmpty && cleanupWarnings.isEmpty && completedItems.count == activePlans.count && !activePlans.contains(where: \.replacesExistingDestination)
        let recovery: FileOperationRecovery?
        switch kind {
        case .move where canRecover:
            recovery = undoPlanBuilder.move(activePlans.map { (source: $0.source, destination: $0.destination) })
        case .copy where canRecover:
            let items = activePlans.map { plan in
                FileOperationRecovery.Item(originalURL: plan.source, destinationURL: plan.destination, destinationIdentity: itemIdentity(at: plan.destination))
            }
            // Provider files without a stable resource identity are explicitly
            // non-undoable: deleting a path alone could delete another item.
            recovery = undoPlanBuilder.copy(items)
        default:
            recovery = nil
        }
        return FileOperationResult(
            completedItems: completedItems,
            skippedItems: skippedItems,
            failedItems: failedItems,
            cleanupWarnings: cleanupWarnings,
            wasCancelled: false,
            recovery: recovery
        )
    }

    private func isUnavailableVolumeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }

    private func safelyCopy(
        source: URL,
        to destination: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        let staging = try makeStagingArea(appropriateFor: destination)
        do {
            var warnings = try await recursivelyCopy(
                source: source, to: staging.stagedItem, topLevelCompletedCount: completedCount, topLevelTotalCount: totalCount,
                recursiveProgress: recursiveProgress, progressHandler: progressHandler
            )
            warnings.append(contentsOf: try placeStagedItem(staging, at: destination))
            warnings.append(contentsOf: cleanupWarnings(for: staging))
            return warnings
        } catch {
            let cleanupWarnings = cleanupWarnings(for: staging)
            throw TransferFailure(underlyingError: error, cleanupWarnings: cleanupWarnings)
        }
    }

    private func safelyMove(
        source: URL,
        to destination: URL,
        replacingExistingDestination: Bool,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        guard replacingExistingDestination else {
            do {
                try descriptorOperator.rename(source, to: destination)
                if recursiveProgress.totalItemCount != nil {
                    // A successful same-volume rename has no byte stream. The
                    // aggregate byte total is therefore intentionally unknown
                    // unless a copy fallback is used.
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(
                        currentItem: source,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        recursiveProgress: recursiveProgress,
                        progressHandler: progressHandler
                    )
                }
                return []
            } catch {
                guard shouldFallbackToCopyDelete(forMoveError: error) else {
                    throw error
                }
                return try await copyThenDeleteMove(
                    source: source,
                    to: destination,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    recursiveProgress: recursiveProgress,
                    progressHandler: progressHandler
                )
            }
        }

        return try await copyThenDeleteMove(
            source: source,
            to: destination,
            completedCount: completedCount,
            totalCount: totalCount,
            recursiveProgress: recursiveProgress,
            progressHandler: progressHandler
        )
    }

    private func copyThenDeleteMove(
        source: URL,
        to destination: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        let staging = try makeStagingArea(appropriateFor: destination)
        do {
            var warnings = try await recursivelyCopy(
                source: source, to: staging.stagedItem, topLevelCompletedCount: completedCount, topLevelTotalCount: totalCount,
                recursiveProgress: recursiveProgress, progressHandler: progressHandler
            )
            warnings.append(contentsOf: try placeStagedItem(staging, at: destination))
            do {
                try descriptorOperator.remove(source)
            } catch {
                warnings.append(FileOperationCleanupWarning(
                    url: source,
                    message: FileOperationError.sourceCleanupFailed(source: source, destination: destination).failureReason ?? error.localizedDescription
                ))
            }
            warnings.append(contentsOf: cleanupWarnings(for: staging))
            return warnings
        } catch {
            let cleanupWarnings = cleanupWarnings(for: staging)
            throw TransferFailure(underlyingError: error, cleanupWarnings: cleanupWarnings)
        }
    }

    private func cleanupWarnings(for staging: StagingArea) -> [FileOperationCleanupWarning] {
        // Refuse to remove an unmarked directory, even if a provider recycled
        // or redirected the URL after allocation.
        guard staging.isOwned(using: fileManager) else { return [] }
        stagingRegistry.setState(.completed, operationID: staging.operationID)
        do {
            try removeIfExists(staging.stagedItem)
            try removeIfExists(staging.backupItem)
            // Keep the ownership marker present while FileManager removes the
            // operation directory as a unit. A failed final removal therefore
            // remains identifiable for a later, explicitly owned cleanup.
            try fileManager.removeItem(at: staging.directory)
            stagingRegistry.remove(operationID: staging.operationID)
            return []
        } catch {
            DiagnosticLogger.log(.warning, category: "FileOperation", "Cleanup warning: could not remove managed staging area at \(DiagnosticLogger.sanitizedPath(staging.directory)); reason=\(error.localizedDescription)")
            return [FileOperationCleanupWarning(
                url: staging.directory,
                message: "PulseFiles could not remove its managed staging area at %@. Review it and remove it manually after confirming it is no longer needed.".localized(with: staging.directory.path)
            )]
        }
    }

    /// Directory enumeration and metadata reads can be expensive (and can
    /// block on network volumes), so plan them off the caller's actor.
    private func calculateTransferMetadata(
        for urls: [URL],
        preparationProgress: (@Sendable (Int, URL) async -> Void)? = nil
    ) async throws -> TransferMetadata? {
        let fileManager = self.fileManager
        let limits = traversalLimits
        let worker = Task.detached(priority: .utility) { () throws -> TransferMetadata? in
            func itemKind(at url: URL) throws -> SourceItemKind {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values.isSymbolicLink == true {
                    return .symbolicLink(destination: try fileManager.destinationOfSymbolicLink(atPath: url.path))
                }
                return values.isDirectory == true ? .directory : .file
            }

            var itemCount = 0
            var byteCount: Int64 = 0
            var hasUnknownByteCount = false
            var work = urls.reversed().map { (url: $0, depth: 0) }
            while let item = work.popLast() {
                try Task.checkCancellation()
                guard item.depth <= limits.maximumDepth, itemCount < limits.maximumItems else {
                    throw FileOperationError.traversalLimitExceeded(item.url, maximumDepth: limits.maximumDepth, maximumItems: limits.maximumItems)
                }
                itemCount += 1
                if itemCount == 1 || itemCount.isMultiple(of: 128) {
                    await preparationProgress?(itemCount, item.url)
                }
                guard let kind = try? itemKind(at: item.url) else { hasUnknownByteCount = true; continue }
                switch kind {
                case .file:
                    let values = try? item.url.resourceValues(forKeys: [.fileSizeKey])
                    if let size = values?.fileSize { byteCount += Int64(size) } else { hasUnknownByteCount = true }
                case .symbolicLink:
                    break // Link metadata describes the link itself, not its target.
                case .finderAlias:
                    // Alias resource forks are not reliably represented by the
                    // data-fork size, so do not make a false capacity claim.
                    hasUnknownByteCount = true
                case .directory:
                    try Task.checkCancellation() // Check immediately before a potentially blocking read.
                    guard let children = try? fileManager.contentsOfDirectory(at: item.url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: []) else {
                        hasUnknownByteCount = true
                        continue
                    }
                    for child in children.reversed() {
                        try Task.checkCancellation() // Check before queueing every child.
                        work.append((child, item.depth + 1))
                    }
                }
            }
            return TransferMetadata(itemCount: itemCount, byteCount: hasUnknownByteCount ? nil : byteCount)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func recursivelyCopy(
        source: URL,
        to destination: URL,
        topLevelCompletedCount: Int,
        topLevelTotalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        enum WorkItem {
            case enter(source: URL, destination: URL, depth: Int)
            case exitDirectory(source: URL, destination: URL)
        }

        var warnings: [FileOperationCleanupWarning] = []
        var work: [WorkItem] = [.enter(source: source, destination: destination, depth: 0)]
        var visitedItemCount = 0
        while let item = work.popLast() {
            try Task.checkCancellation()
            switch item {
            case .exitDirectory(let source, let destination):
                // Child creation changes a directory's timestamps, so restore it post-order.
                warnings.append(contentsOf: preserveMetadata(from: source, to: destination))
            case .enter(let source, let destination, let depth):
                guard depth <= traversalLimits.maximumDepth, visitedItemCount < traversalLimits.maximumItems else {
                    throw FileOperationError.traversalLimitExceeded(source, maximumDepth: traversalLimits.maximumDepth, maximumItems: traversalLimits.maximumItems)
                }
                visitedItemCount += 1
                switch try sourceItemKind(at: source) {
                case .symbolicLink(let linkDestination):
                    try descriptorOperator.createSymbolicLink(at: destination, destination: linkDestination)
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    warnings.append(contentsOf: preserveMetadata(from: source, to: destination))
                case .finderAlias:
                    // FileManager preserves the Finder alias record and resource
                    // fork without resolving or otherwise touching its target.
                    try fileManager.copyItem(at: source, to: destination)
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                case .directory:
                    try descriptorOperator.create(destination, isDirectory: true)
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    try Task.checkCancellation() // Check immediately before directory read.
                    let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                    work.append(.exitDirectory(source: source, destination: destination))
                    for child in children.reversed() {
                        try Task.checkCancellation() // Check before queueing every child.
                        work.append(.enter(source: child, destination: destination.appendingPathComponent(child.lastPathComponent), depth: depth + 1))
                    }
                case .file:
                    #if os(macOS)
                    if fileManager is FileManager {
                        let parent = try OpenDirectoryCapability(directory: destination.deletingLastPathComponent())
                        defer { parent.close() }
                        let name = destination.lastPathComponent
                        try await streamingCopier.copyFile(from: source, toParent: parent, named: name) { [source] byteCount in
                            try Task.checkCancellation()
                            recursiveProgress.completedByteCount += Int64(byteCount)
                            await self.emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                        }
                    } else {
                        try await streamingCopier.copyFile(from: source, to: destination) { [source] byteCount in
                            try Task.checkCancellation()
                            recursiveProgress.completedByteCount += Int64(byteCount)
                            await self.emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                        }
                    }
                    #else
                    try await streamingCopier.copyFile(from: source, to: destination) { [source] byteCount in
                        try Task.checkCancellation()
                        recursiveProgress.completedByteCount += Int64(byteCount)
                        await self.emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    }
                    #endif
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    warnings.append(contentsOf: preserveMetadata(from: source, to: destination))
                }
            }
        }
        return warnings
    }

    private func preserveMetadata(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        metadataPreserver.preserve(from: source, to: destination)
    }

    private func emitProgress(
        currentItem: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?,
        force: Bool = false
    ) async {
        let isFinalRecursiveUpdate = recursiveProgress.totalItemCount.map {
            recursiveProgress.completedItemCount >= $0
        } ?? false
        let isFinalTopLevelUpdate = completedCount >= totalCount
        guard recursiveProgress.shouldPublishProgress(force: force || isFinalRecursiveUpdate || isFinalTopLevelUpdate) else {
            return
        }
        await progressHandler?(FileOperationProgress(
            currentItemName: currentItem.lastPathComponent,
            completedCount: completedCount,
            totalCount: totalCount,
            completedRecursiveItemCount: recursiveProgress.totalItemCount == nil ? nil : recursiveProgress.completedItemCount,
            totalRecursiveItemCount: recursiveProgress.totalItemCount,
            completedByteCount: recursiveProgress.totalByteCount == nil ? nil : recursiveProgress.completedByteCount,
            totalByteCount: recursiveProgress.totalByteCount
        ))
    }

    private func sourceItemKind(at url: URL) throws -> SourceItemKind {
        if pathSafetyStateProvider(url).isFinderAlias {
            return .finderAlias
        }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            return .symbolicLink(destination: try fileManager.destinationOfSymbolicLink(atPath: url.path))
        }
        return values.isDirectory == true ? .directory : .file
    }

    private func shouldFallbackToCopyDelete(forMoveError error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(POSIXErrorCode.EXDEV.rawValue) {
            return true
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlyingError.domain == NSPOSIXErrorDomain,
           underlyingError.code == Int(POSIXErrorCode.EXDEV.rawValue) {
            return true
        }

        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.Code.featureUnsupported.rawValue {
            return true
        }

        return false
    }

    private func placeStagedItem(_ staging: StagingArea, at destination: URL) throws -> [FileOperationCleanupWarning] {
        guard staging.isOwned(using: fileManager) else {
            throw FileOperationError.temporarySiblingUnavailable(destination: destination, prefix: "managed")
        }
        let stagedURL = staging.stagedItem
        guard fileManager.fileExists(atPath: destination.path) else {
            try descriptorOperator.rename(stagedURL, to: destination)
            return []
        }

        let backupURL = staging.backupItem
        try descriptorOperator.rename(destination, to: backupURL)
        do {
            try descriptorOperator.rename(stagedURL, to: destination)
        } catch {
            try? removeIfExists(stagedURL)
            do {
                try descriptorOperator.rename(backupURL, to: destination)
            } catch {
                throw FileOperationError.unsafeReplacement(destination: destination, backup: backupURL)
            }
            throw error
        }

        // The outer structured cleanup owns the backup and operation
        // directory. Keeping cleanup in one place covers success,
        // cancellation, and every failure edge consistently.
        return []
    }

    private func resolveTransferPlans(
        for request: FileOperationRequest,
        conflictHandler: FileConflictHandler
    ) async throws -> [TransferPlan] {
        var plans: [TransferPlan] = []
        var resolutionForRemainingConflicts: FileConflictResolution?
        var reservedDestinations = Set(request.sources.map {
            FilePathComparison.normalizedPath(request.destinationDirectory.appendingPathComponent($0.lastPathComponent))
        })

        for source in request.sources {
            let originalDestination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let replacesExistingDestination = fileManager.fileExists(atPath: originalDestination.path)
            let resolution: FileConflictResolution
            if replacesExistingDestination {
                let decision: FileConflictResolution
                if let resolutionForRemainingConflicts {
                    decision = resolutionForRemainingConflicts
                } else {
                    decision = await conflictHandler(originalDestination)
                }
                if let appliedResolution = decision.resolutionAppliedToRemainingConflicts {
                    resolutionForRemainingConflicts = appliedResolution
                    resolution = appliedResolution
                } else {
                    resolution = decision
                }
                DiagnosticLogger.log(.info, category: "FileOperation", "Conflict decision: destination=\(DiagnosticLogger.sanitizedPath(originalDestination)); resolution=\(resolution.logValue)")
            } else {
                resolution = .replace
            }

            if resolution == .cancel {
                plans.append(TransferPlan(source: source, destination: originalDestination, conflictResolution: .cancel, replacesExistingDestination: true))
                return plans
            }

            let destination: URL
            if resolution == .keepBoth {
                destination = Self.keepBothDestination(
                    for: originalDestination,
                    reservedDestinations: reservedDestinations,
                    fileExists: { self.fileManager.fileExists(atPath: $0.path) }
                )
            } else {
                destination = originalDestination
            }
            try accessPolicy.validateDestinationAccess(to: destination)
            reservedDestinations.insert(FilePathComparison.normalizedPath(destination))
            plans.append(TransferPlan(
                source: source,
                destination: destination,
                conflictResolution: resolution,
                replacesExistingDestination: resolution == .replace && replacesExistingDestination
            ))
        }

        return plans
    }

    static func keepBothDestination(
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

    private func preflightCreation(rawName: String, in directory: URL, isDirectory: Bool) throws -> URL {
        try validateExistingDirectory(directory)
        try validateWritableMutationTarget(directory)
        try accessPolicy.validateAccess(to: directory)
        let name = try FileNameValidator.validate(rawName, in: directory)
        let destination = directory.appendingPathComponent(name, isDirectory: isDirectory)
        try accessPolicy.validateDestinationAccess(to: destination)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.destinationExists(destination)
        }
        return destination
    }

    /// Access is checked before the provider request and revalidated once it
    /// reports success, preventing a download race from bypassing safety rules.
    private func prepareCloudPlaceholders(for urls: [URL], progressHandler: FileOperationProgressHandler?) async throws {
        for (index, url) in urls.enumerated() where pathSafetyStateProvider(url).isICloudPlaceholder {
            try validateExistingSource(url)
            try validateAvailableSource(url, allowingPlaceholder: true)
            try validateSourceAccess(url)
            await progressHandler?(FileOperationProgress(currentItemName: "Downloading %@".localized(with: url.lastPathComponent), completedCount: index, totalCount: urls.count, isPreparingTransfer: true))
            guard try await cloudDownloadPreparer.prepareDownload(for: url) else {
                throw FileOperationError.iCloudItemNotDownloaded(url)
            }
            try Task.checkCancellation()
            try validateExistingSource(url)
            try validateAvailableSource(url)
            try validateSourceAccess(url)
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: index + 1, totalCount: urls.count, isPreparingTransfer: true))
        }
    }

    private func preflightTransferRequest(_ request: FileOperationRequest, isMove: Bool = false) throws {
        try validateExistingDirectory(request.destinationDirectory)
        try validateWritableMutationTarget(request.destinationDirectory)
        try accessPolicy.validateAccess(to: request.destinationDirectory)

        try preflightMultiSourceSelection(request.sources)
        if isMove {
            for source in request.sources {
                try validateWritableMutationTarget(source.deletingLastPathComponent())
            }
        }

        var normalizedDestinations = Set<String>()
        for source in request.sources {
            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try accessPolicy.validateDestinationAccess(to: destination)
            try validateDestination(destination, for: source)
            let normalizedDestination = FilePathComparison.normalizedPath(destination)
            guard normalizedDestinations.insert(normalizedDestination).inserted else {
                throw FileOperationError.duplicateDestination(destination)
            }
        }
    }

    private func preflightRename(source: URL, destination: URL) throws {
        try validateExistingSource(source)
        try validateAvailableSource(source)
        try validateSourceAccess(source)
        try accessPolicy.validateDestinationAccess(to: destination)
        try validateExistingDirectory(source.deletingLastPathComponent())
        try validateWritableMutationTarget(source.deletingLastPathComponent())
        try validateDestination(destination, for: source)
        if fileManager.fileExists(atPath: destination.path), FilePathComparison.normalizedPath(source) != FilePathComparison.normalizedPath(destination) {
            throw FileOperationError.destinationExists(destination)
        }
    }

    private func preflightDelete(_ urls: [URL]) throws {
        try preflightMultiSourceSelection(urls)
        for url in urls {
            try validateWritableMutationTarget(url.deletingLastPathComponent())
        }
    }

    /// Reject a parent and one of its descendants in the same request. This is
    /// intentionally shared by copy, move, trash, and permanent delete so the
    /// outcome cannot depend on selection order or mutation progress.
    private func preflightMultiSourceSelection(_ urls: [URL]) throws {
        try preflightValidator.validateSelection(urls)

        var normalizedSources = Set<String>()
        for url in urls {
            try validateExistingSource(url)
            try validateAvailableSource(url)
            try validateSourceAccess(url)
            guard normalizedSources.insert(FilePathComparison.normalizedPath(url)).inserted else {
                throw FileOperationError.duplicateSource(url)
            }
        }

        for (ancestorIndex, ancestor) in urls.enumerated() {
            for descendant in urls.dropFirst(ancestorIndex + 1) {
                if FilePathComparison.isSameOrDescendant(descendant, ofDirectory: ancestor) {
                    throw FileOperationError.overlappingSources(ancestor: ancestor, descendant: descendant)
                }
                if FilePathComparison.isSameOrDescendant(ancestor, ofDirectory: descendant) {
                    throw FileOperationError.overlappingSources(ancestor: descendant, descendant: ancestor)
                }
            }
        }
    }

    private func validateExistingSource(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceMissing(url)
        }
    }

    private func validateAvailableSource(_ url: URL, allowingPlaceholder: Bool = false) throws {
        let state = pathSafetyStateProvider(url)
        guard state.isAvailable else { throw FileOperationError.volumeUnavailable(url) }
        guard allowingPlaceholder || !state.isICloudPlaceholder else { throw FileOperationError.iCloudItemNotDownloaded(url) }
    }

    private func validateWritableMutationTarget(_ url: URL) throws {
        let state = pathSafetyStateProvider(url)
        guard state.isAvailable else { throw FileOperationError.volumeUnavailable(url) }
        guard !state.isReadOnlyVolume else { throw FileOperationError.readOnlyVolume(url) }
    }

    private func validateSourceAccess(_ source: URL) throws {
        if case .symbolicLink = try sourceItemKind(at: source) {
            // Access to the link is governed by its containing directory. Do
            // not resolve its target: the copy policy above never traverses it.
            try accessPolicy.validateAccess(to: source.deletingLastPathComponent())
        } else if case .finderAlias = try sourceItemKind(at: source) {
            // An alias target may be outside the selected tree; access applies
            // to the opaque alias object in its containing directory.
            try accessPolicy.validateAccess(to: source.deletingLastPathComponent())
        } else {
            try accessPolicy.validateAccess(to: source)
        }
    }

    private func validateExistingDirectory(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.destinationDirectoryMissing(url)
        }
        guard case .directory? = try? sourceItemKind(at: url) else {
            throw FileOperationError.destinationNotDirectory(url)
        }
    }

    private func validateDestination(_ destination: URL, for source: URL) throws {
        if FilePathComparison.isSameOrDescendant(destination, ofDirectory: source) {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
    }

    private func makeStagingArea(appropriateFor destination: URL) throws -> StagingArea {
        let directory = try replacementDirectoryProvider(destination).standardizedFileURL
        let operationID = UUID()
        let marker = directory.appendingPathComponent(".pulsefiles-operation-\(operationID.uuidString)")
        let staging = StagingArea(
            operationID: operationID,
            directory: directory,
            marker: marker,
            stagedItem: directory.appendingPathComponent("item"),
            backupItem: directory.appendingPathComponent("backup")
        )
        // Both authorization modes validate the allocated URLs in relation to
        // the already-authorized destination before any content is written.
        try accessPolicy.validateManagedStagingArea(directory, appropriateFor: destination)
        try accessPolicy.validateManagedStagingArea(staging.stagedItem, appropriateFor: destination)
        try accessPolicy.validateManagedStagingArea(staging.backupItem, appropriateFor: destination)
        try accessPolicy.validateManagedStagingArea(marker, appropriateFor: destination)
        guard !fileManager.fileExists(atPath: marker.path) else {
            throw FileOperationError.temporarySiblingUnavailable(destination: destination, prefix: "managed")
        }
        try fileManager.createEmptyFile(at: marker)
        let destinationDirectory = destination.deletingLastPathComponent().standardizedFileURL
        guard let stagingIdentity = StagingCleanupService.resourceIdentity(directory),
              let destinationIdentity = StagingCleanupService.resourceIdentity(destinationDirectory) else {
            try? fileManager.removeItem(at: directory)
            throw FileOperationError.temporarySiblingUnavailable(destination: destination, prefix: "managed identity")
        }
        stagingRegistry.register(.init(
            operationID: operationID,
            stagingURL: directory,
            createdAt: Date(),
            destinationURL: destinationDirectory,
            stagingIdentity: stagingIdentity,
            destinationIdentity: destinationIdentity,
            state: .active
        ))
        return staging
    }

    private func removeIfExists(_ url: URL) throws {
        #if os(macOS)
        guard fileManager is FileManager else {
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.removeItem(at: url)
            return
        }
        let parent = try OpenDirectoryCapability(directory: url.deletingLastPathComponent())
        defer { parent.close() }
        do {
            try parent.removeItem(named: url.lastPathComponent)
        } catch let error as POSIXError where error.code == .ENOENT {
            return
        }
        #else
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        #endif
    }

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
    var logValue: String {
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

private extension FileConflictResolution {
    var performsTransfer: Bool {
        self == .replace || self == .keepBoth
    }

    var resolutionAppliedToRemainingConflicts: FileConflictResolution? {
        switch self {
        case .applyToRemainingReplace: return .replace
        case .applyToRemainingSkip: return .skip
        case .applyToRemainingKeepBoth: return .keepBoth
        default: return nil
        }
    }
}

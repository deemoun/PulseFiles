import Foundation
#if os(macOS)
import Darwin
#endif

enum FileOperationError: LocalizedError, Equatable {
    case emptySelection
    case duplicateSource(URL)
    /// Multi-source operations reject overlapping paths instead of attempting
    /// an order-dependent partial mutation of a parent and its descendant.
    case overlappingSources(ancestor: URL, descendant: URL)
    case duplicateDestination(URL)
    case sourceMissing(URL)
    case destinationDirectoryMissing(URL)
    case destinationNotDirectory(URL)
    case destinationInsideSource(source: URL, destination: URL)
    case destinationExists(URL)
    case unsafeReplacement(destination: URL, backup: URL)
    case sourceCleanupFailed(source: URL, destination: URL)
    case temporarySiblingUnavailable(destination: URL, prefix: String)
    case insufficientDestinationCapacity(required: Int64, available: Int64)
    case iCloudItemNotDownloaded(URL)
    case finderAliasUnsupported(URL)
    case readOnlyVolume(URL)
    case volumeUnavailable(URL)
    case traversalLimitExceeded(URL, maximumDepth: Int, maximumItems: Int)
    case undoUnavailable

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No files are selected.".localized
        case .duplicateSource(let url):
            return "%@ is selected more than once.".localized(with: url.lastPathComponent)
        case .overlappingSources(let ancestor, let descendant):
            return "%@ and %@ cannot be selected together.".localized(with: ancestor.lastPathComponent, descendant.lastPathComponent)
        case .duplicateDestination(let url):
            return "Multiple selected items would write to %@.".localized(with: url.lastPathComponent)
        case .sourceMissing(let url):
            return "%@ no longer exists.".localized(with: url.lastPathComponent)
        case .destinationDirectoryMissing:
            return "The destination folder does not exist.".localized
        case .destinationNotDirectory(let url):
            return "%@ is not a folder.".localized(with: url.lastPathComponent)
        case .destinationInsideSource:
            return "Cannot copy or move a folder into itself.".localized
        case .destinationExists(let url):
            return "%@ already exists.".localized(with: url.lastPathComponent)
        case .unsafeReplacement:
            return "Could not safely replace the existing item.".localized
        case .sourceCleanupFailed:
            return "The item was copied, but the original could not be removed.".localized
        case .temporarySiblingUnavailable:
            return "Could not create a safe temporary file name.".localized
        case .insufficientDestinationCapacity:
            return "The destination does not have enough available space.".localized
        case .iCloudItemNotDownloaded(let url):
            return "%@ is stored in iCloud and has not finished downloading.".localized(with: url.lastPathComponent)
        case .finderAliasUnsupported(let url):
            return "%@ is a Finder alias, which PulseFiles 1.0 does not modify.".localized(with: url.lastPathComponent)
        case .readOnlyVolume(let url):
            return "%@ is on a read-only volume.".localized(with: url.lastPathComponent)
        case .volumeUnavailable(let url):
            return "The volume containing %@ is no longer available.".localized(with: url.lastPathComponent)
        case .traversalLimitExceeded(let url, _, _):
            return "%@ is too deeply nested or contains too many items to transfer safely.".localized(with: url.lastPathComponent)
        case .undoUnavailable:
            return "This operation can no longer be safely undone.".localized
        }
    }

    private static func formattedByteCount(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    var failureReason: String? {
        switch self {
        case .emptySelection:
            return "Select one or more items in the active pane.".localized
        case .duplicateSource(let url):
            return "PulseFiles rejected the operation before changing files because %@ appeared more than once.".localized(with: url.path)
        case .overlappingSources(let ancestor, let descendant):
            return "PulseFiles rejected the operation before changing files because %@ contains %@.".localized(with: ancestor.path, descendant.path)
        case .duplicateDestination(let url):
            return "PulseFiles rejected the operation before changing files because more than one source would write to %@.".localized(with: url.path)
        case .sourceMissing(let url):
            return "%@ was not found before the operation started.".localized(with: url.path)
        case .destinationDirectoryMissing(let url):
            return "%@ was not found before the operation started.".localized(with: url.path)
        case .destinationNotDirectory(let url):
            return "%@ must be a folder.".localized(with: url.path)
        case .destinationInsideSource(let source, let destination):
            return "Cannot copy or move %@ into %@.".localized(with: source.lastPathComponent, destination.path)
        case .destinationExists(let url):
            return "The destination already contains %@.".localized(with: url.lastPathComponent)
        case .unsafeReplacement(let destination, let backup):
            return "The original item was kept at %@. %@ was not overwritten.".localized(with: backup.path, destination.path)
        case .sourceCleanupFailed(let source, let destination):
            return "%@ now exists, but the original remains at %@.".localized(with: destination.path, source.path)
        case .temporarySiblingUnavailable(let destination, let prefix):
            return "PulseFiles tried multiple %@ staging names beside %@, but each candidate already existed.".localized(with: prefix, destination.path)
        case .insufficientDestinationCapacity(let required, let available):
            return "This operation requires %@, but the destination volume has only %@ available.".localized(with: Self.formattedByteCount(required), Self.formattedByteCount(available))
        case .iCloudItemNotDownloaded(let url):
            return "Download %@ in Finder, then try again. PulseFiles did not change any files.".localized(with: url.path)
        case .finderAliasUnsupported(let url):
            return "Use Finder to copy, move, rename, or delete %@, or operate on the original item instead. PulseFiles did not change any files.".localized(with: url.path)
        case .readOnlyVolume(let url):
            return "Choose a writable destination or eject the read-only media before modifying %@.".localized(with: url.path)
        case .volumeUnavailable(let url):
            return "Reconnect or remount the volume containing %@, then try again.".localized(with: url.path)
        case .traversalLimitExceeded(let url, let maximumDepth, let maximumItems):
            return "PulseFiles stopped before exhausting process resources while traversing %@. The safety limits are a depth of %@ and %@ items.".localized(with: url.path, String(maximumDepth), String(maximumItems))
        case .undoUnavailable:
            return "The operation was partial, cancelled, or did not retain a complete safe reversal path.".localized
        }
    }
}

/// Snapshot used to reject states that cannot safely be mutated.  It is
/// injectable so tests can cover removable, network, and iCloud conditions
/// without depending on the machine running the tests.
struct FileOperationPathSafetyState: Equatable {
    var isAvailable = true
    var isReadOnlyVolume = false
    var isICloudPlaceholder = false
    /// Finder aliases are not symbolic links. Their resolution and resource-fork
    /// semantics are intentionally not a 1.0 mutation guarantee.
    var isFinderAlias = false
}

enum FileConflictResolution: Equatable {
    case replace
    case skip
    case keepBoth
    case cancel
    case applyToRemainingReplace
    case applyToRemainingSkip
    case applyToRemainingKeepBoth
}

enum FileTransferCapacityPreflight: Equatable {
    case notRequired
    case sufficient(required: Int64, available: Int64)
    case insufficient(required: Int64, available: Int64)
    case cannotVerify(required: Int64?)
}

struct FileOperationRequest {
    let sources: [URL]
    let destinationDirectory: URL
}

struct FileOperationProgress {
    let currentItemName: String
    let completedCount: Int
    let totalCount: Int
    let completedRecursiveItemCount: Int?
    let totalRecursiveItemCount: Int?
    let completedByteCount: Int64?
    let totalByteCount: Int64?
    let isPreparingTransfer: Bool

    init(
        currentItemName: String,
        completedCount: Int,
        totalCount: Int,
        completedRecursiveItemCount: Int? = nil,
        totalRecursiveItemCount: Int? = nil,
        completedByteCount: Int64? = nil,
        totalByteCount: Int64? = nil,
        isPreparingTransfer: Bool = false
    ) {
        self.currentItemName = currentItemName
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.completedRecursiveItemCount = completedRecursiveItemCount
        self.totalRecursiveItemCount = totalRecursiveItemCount
        self.completedByteCount = completedByteCount
        self.totalByteCount = totalByteCount
        self.isPreparingTransfer = isPreparingTransfer
    }
}

struct FileOperationItemFailure {
    let url: URL
    let error: Error
}

struct FileOperationCleanupWarning {
    let url: URL
    let message: String
}

struct FileOperationResult {
    let completedItems: [URL]
    let skippedItems: [URL]
    let failedItems: [FileOperationItemFailure]
    let cleanupWarnings: [FileOperationCleanupWarning]
    let wasCancelled: Bool
    /// `true` means the caller stopped waiting while a filesystem call could
    /// still be running. The resulting paths must be verified before reuse.
    let needsVerification: Bool
    let recovery: FileOperationRecovery?

    init(
        completedItems: [URL],
        skippedItems: [URL],
        failedItems: [FileOperationItemFailure],
        cleanupWarnings: [FileOperationCleanupWarning] = [],
        wasCancelled: Bool,
        needsVerification: Bool = false,
        recovery: FileOperationRecovery? = nil
    ) {
        self.completedItems = completedItems
        self.skippedItems = skippedItems
        self.failedItems = failedItems
        self.cleanupWarnings = cleanupWarnings
        self.wasCancelled = wasCancelled
        self.needsVerification = needsVerification
        self.recovery = recovery
    }

    var succeededCompletely: Bool {
        !wasCancelled && !needsVerification && skippedItems.isEmpty && failedItems.isEmpty && cleanupWarnings.isEmpty
    }

    static func unknownAfterAbandoning(currentItem: URL? = nil) -> Self {
        Self(
            completedItems: [],
            skippedItems: [],
            failedItems: [],
            wasCancelled: false,
            needsVerification: true
        )
    }
}

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

protocol FileOperationServicing {
    func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func createFolder(named rawName: String, in directory: URL) throws -> URL
    func createFile(named rawName: String, in directory: URL) throws -> URL
    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
}

protocol FileOperationFileManaging {
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at URL: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws
    func createEmptyFile(at url: URL) throws
    func destinationOfSymbolicLink(atPath path: String) throws -> String
    func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws
    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
}

/// The byte-oriented part of a transfer is deliberately separate from the
/// filesystem coordinator so it can be exercised without relying on
/// `FileManager.copyItem`'s opaque progress behaviour.
protocol FileOperationStreamingCopying {
    func copyFile(
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int) async throws -> Void
    ) async throws
}

final class FileHandleStreamingCopier: FileOperationStreamingCopying {
    private let chunkSize = 1_048_576

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        // FileHandle reads and writes can block, particularly for network
        // volumes. Use a detached executor even when this copier is used
        // independently of FileOperationService.
        let worker = Task.detached(priority: .utility) { [chunkSize = self.chunkSize] in
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let writer = try FileHandle(forWritingTo: destination)
            defer { try? writer.close() }

            while true {
                try Task.checkCancellation()
                guard let data = try reader.read(upToCount: chunkSize), !data.isEmpty else { break }
                try writer.write(contentsOf: data)
                try await progress(data.count)
            }
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

extension FileManager: FileOperationFileManaging {
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }

    func createEmptyFile(at url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
    }
}

final class FileOperationService: FileOperationServicing {
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
    private let traversalLimits: TraversalLimits

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationService.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationService.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationService.defaultPathSafetyState, traversalLimits: TraversalLimits = .init()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.streamingCopier = streamingCopier
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.traversalLimits = traversalLimits
    }

    init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy, streamingCopier: FileOperationStreamingCopying = FileHandleStreamingCopier(), destinationCapacityProvider: @escaping (URL) -> Int64? = FileOperationService.defaultDestinationCapacity, volumeIdentifierProvider: @escaping (URL) -> String? = FileOperationService.defaultVolumeIdentifier, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState = FileOperationService.defaultPathSafetyState, traversalLimits: TraversalLimits = .init()) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.streamingCopier = streamingCopier
        self.destinationCapacityProvider = destinationCapacityProvider
        self.volumeIdentifierProvider = volumeIdentifierProvider
        self.pathSafetyStateProvider = pathSafetyStateProvider
        self.traversalLimits = traversalLimits
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
                try fileManager.moveItem(at: source, to: destination)
            }
            await progressHandler?(FileOperationProgress(currentItemName: destination.lastPathComponent, completedCount: 1, totalCount: 1))
            let result = FileOperationResult(completedItems: [destination], skippedItems: [], failedItems: [], wasCancelled: false, recovery: FileOperationRecovery(kind: .rename, items: [.init(originalURL: source, destinationURL: destination)]))
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
        guard !recovery.items.isEmpty else { throw FileOperationError.undoUnavailable }
        for item in recovery.items {
            try validateExistingSource(item.destinationURL)
            try validateAvailableSource(item.destinationURL)
            try validateExistingDirectory(item.originalURL.deletingLastPathComponent())
            try validateWritableMutationTarget(item.destinationURL.deletingLastPathComponent())
            try validateWritableMutationTarget(item.originalURL.deletingLastPathComponent())
            try accessPolicy.validateAccess(to: item.destinationURL)
            try accessPolicy.validateDestinationAccess(to: item.originalURL)
            if fileManager.fileExists(atPath: item.originalURL.path) { throw FileOperationError.destinationExists(item.originalURL) }
        }
        return try await accessPolicy.withAccess(to: recovery.items.flatMap { [$0.destinationURL, $0.originalURL.deletingLastPathComponent()] }) {
            var completed: [URL] = []
            for (index, item) in recovery.items.enumerated() {
                try Task.checkCancellation()
                await progressHandler?(FileOperationProgress(currentItemName: item.destinationURL.lastPathComponent, completedCount: index, totalCount: recovery.items.count))
                try fileManager.moveItem(at: item.destinationURL, to: item.originalURL)
                completed.append(item.originalURL)
            }
            return FileOperationResult(completedItems: completed, skippedItems: [], failedItems: [], wasCancelled: false)
        }
    }

    func createFolder(named rawName: String, in directory: URL) throws -> URL {
        let destination = try preflightCreation(rawName: rawName, in: directory, isDirectory: true)
        DiagnosticLogger.log(.info, category: "FileOperation", "Create folder operation starting: destination=\(DiagnosticLogger.sanitizedPath(destination))")
        do {
            try accessPolicy.withAccess(to: [directory]) {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            }
            return destination
        } catch {
            DiagnosticLogger.log(.error, category: "FileOperation", "Create folder operation failed: destination=\(DiagnosticLogger.sanitizedPath(destination)); reason=\(error.localizedDescription)")
            throw error
        }
    }

    func createFile(named rawName: String, in directory: URL) throws -> URL {
        let destination = try preflightCreation(rawName: rawName, in: directory, isDirectory: false)
        DiagnosticLogger.log(.info, category: "FileOperation", "Create file operation starting: destination=\(DiagnosticLogger.sanitizedPath(destination))")
        do {
            try accessPolicy.withAccess(to: [directory]) {
                try fileManager.createEmptyFile(at: destination)
            }
            return destination
        } catch {
            DiagnosticLogger.log(.error, category: "FileOperation", "Create file operation failed: destination=\(DiagnosticLogger.sanitizedPath(destination)); reason=\(error.localizedDescription)")
            throw error
        }
    }

    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Trash operation starting: itemCount=\(urls.count)")
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "trash", error: error); throw error }
        let result = await accessPolicy.withAccess(to: urls) {
            await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
                #if os(macOS)
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                #else
                throw CocoaError(.featureUnsupported)
                #endif
            }
        }
        logCompletion(operation: "trash", result: result)
        return result
    }

    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation starting: itemCount=\(urls.count)")
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "delete", error: error); throw error }
        let result = await accessPolicy.withAccess(to: urls) {
            await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
                try fileManager.removeItem(at: url)
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
        var completedItems: [URL] = []
        var failedItems: [FileOperationItemFailure] = []
        let totalCount = urls.count
        var completedCount = 0

        for url in urls {
            if Task.isCancelled {
                DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation cancelled: completedCount=\(completedItems.count); failedCount=\(failedItems.count)")
                return FileOperationResult(completedItems: completedItems, skippedItems: [], failedItems: failedItems, wasCancelled: true)
            }
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
            guard fileManager.fileExists(atPath: url.path) else {
                failedItems.append(FileOperationItemFailure(url: url, error: FileOperationError.sourceMissing(url)))
                break
            }
            do {
                try validateAvailableSource(url)
                try validateWritableMutationTarget(url.deletingLastPathComponent())
            } catch {
                failedItems.append(FileOperationItemFailure(url: url, error: error))
                break
            }
            do {
                try operation(fileManager, url)
                completedItems.append(url)
            } catch {
                DiagnosticLogger.log(.error, category: "FileOperation", "Item operation failed: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(error.localizedDescription)")
                failedItems.append(FileOperationItemFailure(url: url, error: error))
                if isUnavailableVolumeError(error) {
                    break
                }
            }
            completedCount += 1
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
        }

        return FileOperationResult(completedItems: completedItems, skippedItems: [], failedItems: failedItems, wasCancelled: false)
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
        var recursiveProgress = RecursiveProgressState(
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

        let recovery: FileOperationRecovery? = kind == .move && skippedItems.isEmpty && failedItems.isEmpty && cleanupWarnings.isEmpty && completedItems.count == activePlans.count && !activePlans.contains(where: \.replacesExistingDestination)
            ? FileOperationRecovery(kind: .move, items: activePlans.map { .init(originalURL: $0.source, destinationURL: $0.destination) })
            : nil
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
        let tempURL = try uniqueTemporarySibling(for: destination, prefix: ".pulsefiles-copy")
        do {
            var warnings = try await recursivelyCopy(
                source: source, to: tempURL, topLevelCompletedCount: completedCount, topLevelTotalCount: totalCount,
                recursiveProgress: recursiveProgress, progressHandler: progressHandler
            )
            warnings.append(contentsOf: try placeStagedItem(tempURL, at: destination))
            return warnings
        } catch {
            let cleanupWarnings = cleanupWarningsAfterFailedStagingRemoval(at: tempURL)
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
                try fileManager.moveItem(at: source, to: destination)
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
        let tempURL = try uniqueTemporarySibling(for: destination, prefix: ".pulsefiles-move")
        do {
            var warnings = try await recursivelyCopy(
                source: source, to: tempURL, topLevelCompletedCount: completedCount, topLevelTotalCount: totalCount,
                recursiveProgress: recursiveProgress, progressHandler: progressHandler
            )
            warnings.append(contentsOf: try placeStagedItem(tempURL, at: destination))
            do {
                try fileManager.removeItem(at: source)
            } catch {
                warnings.append(FileOperationCleanupWarning(
                    url: source,
                    message: FileOperationError.sourceCleanupFailed(source: source, destination: destination).failureReason ?? error.localizedDescription
                ))
            }
            return warnings
        } catch {
            let cleanupWarnings = cleanupWarningsAfterFailedStagingRemoval(at: tempURL)
            throw TransferFailure(underlyingError: error, cleanupWarnings: cleanupWarnings)
        }
    }

    private func cleanupWarningsAfterFailedStagingRemoval(at temporaryURL: URL) -> [FileOperationCleanupWarning] {
        do {
            try removeIfExists(temporaryURL)
            return []
        } catch {
            DiagnosticLogger.log(.warning, category: "FileOperation", "Cleanup warning: could not remove temporary item at \(DiagnosticLogger.sanitizedPath(temporaryURL)); reason=\(error.localizedDescription)")
            return [FileOperationCleanupWarning(
                url: temporaryURL,
                message: "PulseFiles could not remove the temporary item at %@. Review it and remove it manually after confirming it is no longer needed.".localized(with: temporaryURL.path)
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
                    try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: linkDestination)
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    warnings.append(contentsOf: preserveMetadata(from: source, to: destination))
                case .directory:
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
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
                    try await streamingCopier.copyFile(from: source, to: destination) { [source] byteCount in
                        try Task.checkCancellation()
                        recursiveProgress.completedByteCount += Int64(byteCount)
                        await self.emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    }
                    recursiveProgress.completedItemCount += 1
                    await emitProgress(currentItem: source, completedCount: topLevelCompletedCount, totalCount: topLevelTotalCount, recursiveProgress: recursiveProgress, progressHandler: progressHandler)
                    warnings.append(contentsOf: preserveMetadata(from: source, to: destination))
                }
            }
        }
        return warnings
    }

    /// Preserve metadata after content. Metadata failures are reported as warnings so
    /// a copied item is never presented as completely successful when it lost data.
    private func preserveMetadata(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        var warnings: [FileOperationCleanupWarning] = []
        do {
            let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
            let attributes = sourceAttributes.filter { [.posixPermissions, .ownerAccountID, .groupOwnerAccountID, .creationDate, .modificationDate].contains($0.key) }
            try FileManager.default.setAttributes(attributes, ofItemAtPath: destination.path)
        } catch {
            warnings.append(metadataWarning(for: destination, error: error))
        }
        do {
            let sourceValues = try source.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
            if sourceValues.labelNumber != nil {
                var values = URLResourceValues()
                values.labelNumber = sourceValues.labelNumber
                var destinationURL = destination
                try destinationURL.setResourceValues(values)
            }
        } catch {
            warnings.append(metadataWarning(for: destination, error: error))
        }
        #if os(macOS)
        warnings.append(contentsOf: copyExtendedAttributes(from: source, to: destination))
        warnings.append(contentsOf: copyAccessControlList(from: source, to: destination))
        #endif
        return warnings
    }

    private func metadataWarning(for url: URL, error: Error) -> FileOperationCleanupWarning {
        FileOperationCleanupWarning(url: url, message: "PulseFiles copied item contents but could not preserve all metadata at %@: %@".localized(with: url.path, error.localizedDescription))
    }

    #if os(macOS)
    private func copyExtendedAttributes(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        let options = Int32(XATTR_NOFOLLOW)
        let size = listxattr(source.path, nil, 0, options)
        guard size >= 0 else { return metadataWarnings(for: source, errno: errno) }
        guard size > 0 else { return [] }
        var names = [CChar](repeating: 0, count: size)
        guard listxattr(source.path, &names, names.count, options) >= 0 else { return metadataWarnings(for: source, errno: errno) }
        var warnings: [FileOperationCleanupWarning] = []
        var offset = 0
        while offset < names.count {
            let name = String(cString: &names[offset]); offset += name.utf8.count + 1
            let valueSize = getxattr(source.path, name, nil, 0, 0, options)
            guard valueSize >= 0 else { warnings.append(contentsOf: metadataWarnings(for: source, errno: errno)); continue }
            var value = [UInt8](repeating: 0, count: valueSize)
            guard getxattr(source.path, name, &value, value.count, 0, options) >= 0,
                  setxattr(destination.path, name, value, value.count, 0, options) == 0 else {
                warnings.append(contentsOf: metadataWarnings(for: destination, errno: errno)); continue
            }
        }
        return warnings
    }

    private func copyAccessControlList(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        guard copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_ACL)) == 0 else { return metadataWarnings(for: destination, errno: errno) }
        return []
    }

    private func metadataWarnings(for url: URL, errno code: Int32) -> [FileOperationCleanupWarning] {
        guard code != ENOTSUP && code != EOPNOTSUPP else { return [] }
        return [metadataWarning(for: url, error: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))]
    }
    #endif

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

    private func placeStagedItem(_ stagedURL: URL, at destination: URL) throws -> [FileOperationCleanupWarning] {
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: stagedURL, to: destination)
            return []
        }

        let backupURL = try uniqueTemporarySibling(for: destination, prefix: ".pulsefiles-backup")
        try fileManager.moveItem(at: destination, to: backupURL)
        do {
            try fileManager.moveItem(at: stagedURL, to: destination)
        } catch {
            try? removeIfExists(stagedURL)
            do {
                try fileManager.moveItem(at: backupURL, to: destination)
            } catch {
                throw FileOperationError.unsafeReplacement(destination: destination, backup: backupURL)
            }
            throw error
        }

        do {
            try fileManager.removeItem(at: backupURL)
            return []
        } catch {
            DiagnosticLogger.log(.warning, category: "FileOperation", "Cleanup warning: could not remove replacement backup at \(DiagnosticLogger.sanitizedPath(backupURL)); reason=\(error.localizedDescription)")
            return [FileOperationCleanupWarning(
                url: backupURL,
                message: "The old item was replaced, but PulseFiles could not remove the backup at %@.".localized(with: backupURL.path)
            )]
        }
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
        let originalName = destination.lastPathComponent
        let fileExtension = destination.pathExtension
        let baseName = fileExtension.isEmpty
            ? originalName
            : destination.deletingPathExtension().lastPathComponent

        var copyIndex = 1
        while true {
            let suffix = copyIndex == 1 ? " copy" : " copy \(copyIndex)"
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(fileExtension)"
            let candidate = destination.deletingLastPathComponent().appendingPathComponent(candidateName)
            if !fileExists(candidate), !reservedDestinations.contains(FilePathComparison.normalizedPath(candidate)) {
                return candidate
            }
            copyIndex += 1
        }
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
            if fileManager.fileExists(atPath: destination.path) {
                try validateNotFinderAlias(destination)
            }
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
            try validateNotFinderAlias(destination)
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
        guard !urls.isEmpty else { throw FileOperationError.emptySelection }

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

    private func validateAvailableSource(_ url: URL) throws {
        let state = pathSafetyStateProvider(url)
        guard state.isAvailable else { throw FileOperationError.volumeUnavailable(url) }
        guard !state.isICloudPlaceholder else { throw FileOperationError.iCloudItemNotDownloaded(url) }
        guard !state.isFinderAlias else { throw FileOperationError.finderAliasUnsupported(url) }
    }

    private func validateNotFinderAlias(_ url: URL) throws {
        guard !pathSafetyStateProvider(url).isFinderAlias else { throw FileOperationError.finderAliasUnsupported(url) }
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

    private func uniqueTemporarySibling(for destination: URL, prefix: String, maximumAttempts: Int = 10) throws -> URL {
        let parentDirectory = destination.deletingLastPathComponent()
        for _ in 0..<maximumAttempts {
            let candidate = parentDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)-\(destination.lastPathComponent)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw FileOperationError.temporarySiblingUnavailable(destination: destination, prefix: prefix)
    }

    private func removeIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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

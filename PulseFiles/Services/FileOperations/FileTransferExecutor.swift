import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

/// Executes transfers only after the facade has acquired operation-level access
/// and the preflight validator and planner have approved the request.
package final class FileTransferExecutor {
    package enum TransferKind { case copy, move }
    private struct TransferFailure: Error { let underlyingError: Error; let cleanupWarnings: [FileOperationCleanupWarning] }
    package struct TransferMetadata: Sendable { let itemCount: Int; let byteCount: Int64? }
    /// A policy-validated, same-volume directory owned by one transfer.
    package struct StagingArea {
        let operationID: UUID; let directory: URL; let marker: URL; let stagedItem: URL; let backupItem: URL
        func isOwned(using fileManager: FileOperationFileManaging) -> Bool { fileManager.fileExists(atPath: marker.path) }
    }
    /// Throttles recursive byte/item updates before they reach the main actor.
    package final class RecursiveProgressState {
        private static let minimumUpdateInterval: TimeInterval = 1.0 / 15.0
        let totalItemCount: Int?; var completedItemCount: Int; let totalByteCount: Int64?; var completedByteCount: Int64
        private var lastProgressUpdate = Date.distantPast
        init(totalItemCount: Int?, completedItemCount: Int, totalByteCount: Int64?, completedByteCount: Int64) { self.totalItemCount=totalItemCount; self.completedItemCount=completedItemCount; self.totalByteCount=totalByteCount; self.completedByteCount=completedByteCount }
        func shouldPublishProgress(force: Bool) -> Bool { let now=Date(); guard force || now.timeIntervalSince(lastProgressUpdate) >= Self.minimumUpdateInterval else { return false }; lastProgressUpdate=now; return true }
    }
    package let fileManager: FileOperationFileManaging
    package let streamingCopier: FileOperationStreamingCopying
    package let descriptorOperator: DescriptorRelativeFileOperator
    private let preflightValidator: FileOperationPreflightValidator
    private let metadataPreserver: FileMetadataPreserver
    private let accessPolicy: SandboxFileAccessPolicy
    private let pathSafetyStateProvider: (URL) -> FileOperationPathSafetyState
    private let traversalLimits: FileOperationService.TraversalLimits
    private let replacementDirectoryProvider: (URL) throws -> URL
    private let stagingRegistry: StagingOwnershipRegistry
    private let undoPlanBuilder = FileOperationUndoPlanBuilder()

    package init(fileManager: FileOperationFileManaging, streamingCopier: FileOperationStreamingCopying, descriptorOperator: DescriptorRelativeFileOperator, preflightValidator: FileOperationPreflightValidator, metadataPreserver: FileMetadataPreserver, accessPolicy: SandboxFileAccessPolicy, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState, traversalLimits: FileOperationService.TraversalLimits, replacementDirectoryProvider: @escaping (URL) throws -> URL, stagingRegistry: StagingOwnershipRegistry) {
        self.fileManager=fileManager; self.streamingCopier=streamingCopier; self.descriptorOperator=descriptorOperator; self.preflightValidator=preflightValidator; self.metadataPreserver=metadataPreserver; self.accessPolicy=accessPolicy; self.pathSafetyStateProvider=pathSafetyStateProvider; self.traversalLimits=traversalLimits; self.replacementDirectoryProvider=replacementDirectoryProvider; self.stagingRegistry=stagingRegistry
    }
    package func performTransfer(
        _ plans: [FileTransferPlanner.TransferPlan],
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
                try preflightValidator.validateAvailableSource(plan.source)
                try preflightValidator.validateWritableMutationTarget(plan.destination.deletingLastPathComponent())
                if kind == .move {
                    try preflightValidator.validateWritableMutationTarget(plan.source.deletingLastPathComponent())
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
                FileOperationRecovery.Item(originalURL: plan.source, destinationURL: plan.destination, destinationIdentity: preflightValidator.itemIdentity(at: plan.destination))
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

    package func calculateTransferMetadata(
        for urls: [URL],
        preparationProgress: (@Sendable (Int, URL) async -> Void)? = nil
    ) async throws -> TransferMetadata? {
        let fileManager = self.fileManager
        let limits = traversalLimits
        let worker = Task.detached(priority: .utility) { () throws -> TransferMetadata? in
            func itemKind(at url: URL) throws -> FileOperationPreflightValidator.SourceItemKind {
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
                switch try preflightValidator.sourceItemKind(at: source) {
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

    package static func systemReplacementDirectory(appropriateFor destination: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
    }
}

private extension FileConflictResolution {
    package var performsTransfer: Bool { self == .replace || self == .keepBoth }
}

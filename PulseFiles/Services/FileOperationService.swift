import Foundation

enum FileOperationError: LocalizedError, Equatable {
    case emptySelection
    case duplicateSource(URL)
    case duplicateDestination(URL)
    case sourceMissing(URL)
    case destinationDirectoryMissing(URL)
    case destinationNotDirectory(URL)
    case destinationInsideSource(source: URL, destination: URL)
    case destinationExists(URL)
    case unsafeReplacement(destination: URL, backup: URL)
    case sourceCleanupFailed(source: URL, destination: URL)
    case temporarySiblingUnavailable(destination: URL, prefix: String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No files are selected.".localized
        case .duplicateSource(let url):
            return "%@ is selected more than once.".localized(with: url.lastPathComponent)
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
        }
    }

    var failureReason: String? {
        switch self {
        case .emptySelection:
            return "Select one or more items in the active pane.".localized
        case .duplicateSource(let url):
            return "PulseFiles rejected the operation before changing files because %@ appeared more than once.".localized(with: url.path)
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
        }
    }
}

enum FileConflictResolution {
    case replace
    case skip
    case cancel
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

    init(
        currentItemName: String,
        completedCount: Int,
        totalCount: Int,
        completedRecursiveItemCount: Int? = nil,
        totalRecursiveItemCount: Int? = nil,
        completedByteCount: Int64? = nil,
        totalByteCount: Int64? = nil
    ) {
        self.currentItemName = currentItemName
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.completedRecursiveItemCount = completedRecursiveItemCount
        self.totalRecursiveItemCount = totalRecursiveItemCount
        self.completedByteCount = completedByteCount
        self.totalByteCount = totalByteCount
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

    init(
        completedItems: [URL],
        skippedItems: [URL],
        failedItems: [FileOperationItemFailure],
        cleanupWarnings: [FileOperationCleanupWarning] = [],
        wasCancelled: Bool
    ) {
        self.completedItems = completedItems
        self.skippedItems = skippedItems
        self.failedItems = failedItems
        self.cleanupWarnings = cleanupWarnings
        self.wasCancelled = wasCancelled
    }

    var succeededCompletely: Bool {
        !wasCancelled && skippedItems.isEmpty && failedItems.isEmpty && cleanupWarnings.isEmpty
    }
}

typealias FileOperationProgressHandler = @MainActor (FileOperationProgress) -> Void
typealias FileConflictHandler = (URL) async -> FileConflictResolution

protocol FileOperationServicing {
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
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
    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
}

extension FileManager: FileOperationFileManaging {
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }
}

final class FileOperationService: FileOperationServicing {
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

    private struct RecursiveProgressState {
        let totalItemCount: Int?
        var completedItemCount: Int
    }

    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    func copy(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Copy operation starting: sourceCount=\(request.sources.count); destination=\(DiagnosticLogger.sanitizedPath(request.destinationDirectory))")
        do {
            try preflightTransferRequest(request)
        } catch {
            logPreflightFailure(operation: "copy", error: error)
            throw error
        }
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            DiagnosticLogger.log(.info, category: "FileOperation", "Copy operation cancelled during conflict resolution: skippedCount=\(plans.filter { $0.conflictResolution == .skip }.count)")
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        let result = await performTransfer(plans, kind: .copy, progressHandler: progressHandler)
        logCompletion(operation: "copy", result: result)
        return result
    }

    func move(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Move operation starting: sourceCount=\(request.sources.count); destination=\(DiagnosticLogger.sanitizedPath(request.destinationDirectory))")
        do {
            try preflightTransferRequest(request)
        } catch {
            logPreflightFailure(operation: "move", error: error)
            throw error
        }
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            DiagnosticLogger.log(.info, category: "FileOperation", "Move operation cancelled during conflict resolution: skippedCount=\(plans.filter { $0.conflictResolution == .skip }.count)")
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        let result = await performTransfer(plans, kind: .move, progressHandler: progressHandler)
        logCompletion(operation: "move", result: result)
        return result
    }

    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        let parentDirectory = source.deletingLastPathComponent()
        try accessPolicy.validateAccess(to: source)
        try accessPolicy.validateAccess(to: parentDirectory)
        try validateExistingSource(source)
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
            try fileManager.moveItem(at: source, to: destination)
            await progressHandler?(FileOperationProgress(currentItemName: destination.lastPathComponent, completedCount: 1, totalCount: 1))
            let result = FileOperationResult(completedItems: [destination], skippedItems: [], failedItems: [], wasCancelled: false)
            logCompletion(operation: "rename", result: result)
            return result
        } catch {
            await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: 1, totalCount: 1))
            let result = FileOperationResult(completedItems: [], skippedItems: [], failedItems: [FileOperationItemFailure(url: source, error: error)], wasCancelled: false)
            logCompletion(operation: "rename", result: result)
            return result
        }
    }

    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Trash operation starting: itemCount=\(urls.count)")
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "trash", error: error); throw error }
        let result = await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            #if os(macOS)
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            #else
            throw CocoaError(.featureUnsupported)
            #endif
        }
        logCompletion(operation: "trash", result: result)
        return result
    }

    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation starting: itemCount=\(urls.count)")
        do { try preflightDelete(urls) } catch { logPreflightFailure(operation: "delete", error: error); throw error }
        let result = await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            try fileManager.removeItem(at: url)
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
            do {
                try operation(fileManager, url)
                completedItems.append(url)
            } catch {
                DiagnosticLogger.log(.error, category: "FileOperation", "Item operation failed: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(error.localizedDescription)")
                failedItems.append(FileOperationItemFailure(url: url, error: error))
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
        let activePlans = plans.filter { $0.conflictResolution == .replace }
        let totalCount = activePlans.count
        var completedCount = 0
        var recursiveProgress = RecursiveProgressState(
            totalItemCount: progressHandler == nil ? nil : preScanRecursiveItemCount(for: activePlans.map(\.source)),
            completedItemCount: 0
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
            do {
                switch kind {
                case .copy:
                    let warnings = try await safelyCopy(
                        source: plan.source,
                        to: plan.destination,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        recursiveProgress: &recursiveProgress,
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
                        recursiveProgress: &recursiveProgress,
                        progressHandler: progressHandler
                    )
                    cleanupWarnings.append(contentsOf: warnings)
                }
                completedItems.append(plan.source)
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

        return FileOperationResult(
            completedItems: completedItems,
            skippedItems: skippedItems,
            failedItems: failedItems,
            cleanupWarnings: cleanupWarnings,
            wasCancelled: false
        )
    }

    private func safelyCopy(
        source: URL,
        to destination: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: inout RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        let tempURL = try uniqueTemporarySibling(for: destination, prefix: ".pulsefiles-copy")
        do {
            try await recursivelyCopy(
                source: source,
                to: tempURL,
                topLevelCompletedCount: completedCount,
                topLevelTotalCount: totalCount,
                recursiveProgress: &recursiveProgress,
                progressHandler: progressHandler
            )
            return try placeStagedItem(tempURL, at: destination)
        } catch {
            try? removeIfExists(tempURL)
            throw error
        }
    }

    private func safelyMove(
        source: URL,
        to destination: URL,
        replacingExistingDestination: Bool,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: inout RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        guard replacingExistingDestination else {
            do {
                let movedItemCount = recursiveProgress.totalItemCount == nil ? 1 : (recursiveItemCount(for: source) ?? 1)
                try fileManager.moveItem(at: source, to: destination)
                if recursiveProgress.totalItemCount != nil {
                    recursiveProgress.completedItemCount += movedItemCount
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
                    recursiveProgress: &recursiveProgress,
                    progressHandler: progressHandler
                )
            }
        }

        return try await copyThenDeleteMove(
            source: source,
            to: destination,
            completedCount: completedCount,
            totalCount: totalCount,
            recursiveProgress: &recursiveProgress,
            progressHandler: progressHandler
        )
    }

    private func copyThenDeleteMove(
        source: URL,
        to destination: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: inout RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> [FileOperationCleanupWarning] {
        let tempURL = try uniqueTemporarySibling(for: destination, prefix: ".pulsefiles-move")
        do {
            try await recursivelyCopy(
                source: source,
                to: tempURL,
                topLevelCompletedCount: completedCount,
                topLevelTotalCount: totalCount,
                recursiveProgress: &recursiveProgress,
                progressHandler: progressHandler
            )
            var warnings = try placeStagedItem(tempURL, at: destination)
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
            try? removeIfExists(tempURL)
            throw error
        }
    }


    private func preScanRecursiveItemCount(for urls: [URL]) -> Int? {
        var total = 0
        for url in urls {
            guard !Task.isCancelled else { return nil }
            total += recursiveItemCount(for: url) ?? 1
        }
        return total
    }

    private func recursiveItemCount(for url: URL) -> Int? {
        guard isDirectory(url) else { return 1 }
        do {
            let children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            var count = 1
            for child in children {
                guard !Task.isCancelled else { return nil }
                count += recursiveItemCount(for: child) ?? 1
            }
            return count
        } catch {
            return 1
        }
    }

    private func recursivelyCopy(
        source: URL,
        to destination: URL,
        topLevelCompletedCount: Int,
        topLevelTotalCount: Int,
        recursiveProgress: inout RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        try Task.checkCancellation()
        if isDirectory(source) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            recursiveProgress.completedItemCount += 1
            await emitProgress(
                currentItem: source,
                completedCount: topLevelCompletedCount,
                totalCount: topLevelTotalCount,
                recursiveProgress: recursiveProgress,
                progressHandler: progressHandler
            )

            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            for child in children {
                try Task.checkCancellation()
                try await recursivelyCopy(
                    source: child,
                    to: destination.appendingPathComponent(child.lastPathComponent, isDirectory: isDirectory(child)),
                    topLevelCompletedCount: topLevelCompletedCount,
                    topLevelTotalCount: topLevelTotalCount,
                    recursiveProgress: &recursiveProgress,
                    progressHandler: progressHandler
                )
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
            recursiveProgress.completedItemCount += 1
            await emitProgress(
                currentItem: source,
                completedCount: topLevelCompletedCount,
                totalCount: topLevelTotalCount,
                recursiveProgress: recursiveProgress,
                progressHandler: progressHandler
            )
        }
    }

    private func emitProgress(
        currentItem: URL,
        completedCount: Int,
        totalCount: Int,
        recursiveProgress: RecursiveProgressState,
        progressHandler: FileOperationProgressHandler?
    ) async {
        await progressHandler?(FileOperationProgress(
            currentItemName: currentItem.lastPathComponent,
            completedCount: completedCount,
            totalCount: totalCount,
            completedRecursiveItemCount: recursiveProgress.totalItemCount == nil ? nil : recursiveProgress.completedItemCount,
            totalRecursiveItemCount: recursiveProgress.totalItemCount
        ))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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
        for source in request.sources {
            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let replacesExistingDestination = fileManager.fileExists(atPath: destination.path)
            let resolution: FileConflictResolution
            if replacesExistingDestination {
                resolution = await conflictHandler(destination)
                DiagnosticLogger.log(.info, category: "FileOperation", "Conflict decision: destination=\(DiagnosticLogger.sanitizedPath(destination)); resolution=\(resolution.logValue)")
            } else {
                resolution = .replace
            }

            if resolution == .cancel {
                plans.append(TransferPlan(source: source, destination: destination, conflictResolution: .cancel, replacesExistingDestination: true))
                return plans
            }
            plans.append(TransferPlan(
                source: source,
                destination: destination,
                conflictResolution: resolution,
                replacesExistingDestination: replacesExistingDestination
            ))
        }

        return plans
    }

    private func preflightTransferRequest(_ request: FileOperationRequest) throws {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        try validateExistingDirectory(request.destinationDirectory)
        try accessPolicy.validateAccess(to: request.destinationDirectory)

        var normalizedSources = Set<String>()
        var normalizedDestinations = Set<String>()
        for source in request.sources {
            try accessPolicy.validateAccess(to: source)
            try validateExistingSource(source)
            let normalizedSource = FilePathComparison.normalizedPath(source)
            guard normalizedSources.insert(normalizedSource).inserted else {
                throw FileOperationError.duplicateSource(source)
            }

            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try accessPolicy.validateAccess(to: destination)
            try validateDestination(destination, for: source)
            let normalizedDestination = FilePathComparison.normalizedPath(destination)
            guard normalizedDestinations.insert(normalizedDestination).inserted else {
                throw FileOperationError.duplicateDestination(destination)
            }
        }
    }

    private func preflightRename(source: URL, destination: URL) throws {
        try accessPolicy.validateAccess(to: source)
        try accessPolicy.validateAccess(to: destination)
        try validateExistingSource(source)
        try validateExistingDirectory(source.deletingLastPathComponent())
        try validateDestination(destination, for: source)
        if fileManager.fileExists(atPath: destination.path), FilePathComparison.normalizedPath(source) != FilePathComparison.normalizedPath(destination) {
            throw FileOperationError.destinationExists(destination)
        }
    }

    private func preflightDelete(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw FileOperationError.emptySelection }
        var normalizedSources = Set<String>()
        for url in urls {
            try accessPolicy.validateAccess(to: url)
            try validateExistingSource(url)
            guard normalizedSources.insert(FilePathComparison.normalizedPath(url)).inserted else {
                throw FileOperationError.duplicateSource(url)
            }
        }
    }

    private func validateExistingSource(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceMissing(url)
        }
    }

    private func validateExistingDirectory(_ url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileOperationError.destinationDirectoryMissing(url)
        }
        guard isDirectory.boolValue else {
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
        case .cancel: return "cancel"
        }
    }
}

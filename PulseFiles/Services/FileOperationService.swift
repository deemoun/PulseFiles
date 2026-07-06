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
            return "Invalid destination.".localized
        case .destinationExists(let url):
            return "%@ already exists.".localized(with: url.lastPathComponent)
        case .unsafeReplacement:
            return "Could not safely replace the existing item.".localized
        case .sourceCleanupFailed:
            return "The item was copied, but the original could not be removed.".localized
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
    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
}

extension FileManager: FileOperationFileManaging {}

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
        try preflightTransferRequest(request)
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await performTransfer(plans, kind: .copy, progressHandler: progressHandler)
    }

    func move(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        try preflightTransferRequest(request)
        let plans = try await resolveTransferPlans(for: request, conflictHandler: conflictHandler)
        if plans.contains(where: { $0.conflictResolution == .cancel }) {
            return FileOperationResult(completedItems: [], skippedItems: plans.filter { $0.conflictResolution == .skip }.map(\.source), failedItems: [], wasCancelled: true)
        }
        return await performTransfer(plans, kind: .move, progressHandler: progressHandler)
    }

    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        let parentDirectory = source.deletingLastPathComponent()
        try accessPolicy.validateAccess(to: source)
        try accessPolicy.validateAccess(to: parentDirectory)
        try validateExistingSource(source)
        try validateExistingDirectory(parentDirectory)

        let destinationName = try FileNameValidator.validate(rawName, in: parentDirectory, replacing: source)
        let destination = parentDirectory.appendingPathComponent(destinationName)

        try preflightRename(source: source, destination: destination)
        await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: 0, totalCount: 1))

        do {
            try fileManager.moveItem(at: source, to: destination)
            await progressHandler?(FileOperationProgress(currentItemName: destination.lastPathComponent, completedCount: 1, totalCount: 1))
            return FileOperationResult(completedItems: [destination], skippedItems: [], failedItems: [], wasCancelled: false)
        } catch {
            await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: 1, totalCount: 1))
            return FileOperationResult(completedItems: [], skippedItems: [], failedItems: [FileOperationItemFailure(url: source, error: error)], wasCancelled: false)
        }
    }

    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try preflightDelete(urls)
        return await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            #if os(macOS)
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            #else
            throw CocoaError(.featureUnsupported)
            #endif
        }
    }

    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try preflightDelete(urls)
        return await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            try fileManager.removeItem(at: url)
        }
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
                return FileOperationResult(completedItems: completedItems, skippedItems: [], failedItems: failedItems, wasCancelled: true)
            }
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
            do {
                try operation(fileManager, url)
                completedItems.append(url)
            } catch {
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

        skippedItems.append(contentsOf: plans.filter { $0.conflictResolution == .skip }.map(\.source))

        for plan in activePlans {
            if Task.isCancelled {
                return FileOperationResult(
                    completedItems: completedItems,
                    skippedItems: skippedItems,
                    failedItems: failedItems,
                    cleanupWarnings: cleanupWarnings,
                    wasCancelled: true
                )
            }

            await progressHandler?(FileOperationProgress(currentItemName: plan.source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
            do {
                switch kind {
                case .copy:
                    let warnings = try safelyCopy(source: plan.source, to: plan.destination)
                    cleanupWarnings.append(contentsOf: warnings)
                case .move:
                    let warnings = try safelyMove(
                        source: plan.source,
                        to: plan.destination,
                        replacingExistingDestination: plan.replacesExistingDestination
                    )
                    cleanupWarnings.append(contentsOf: warnings)
                }
                completedItems.append(plan.source)
            } catch {
                failedItems.append(FileOperationItemFailure(url: plan.source, error: error))
            }
            completedCount += 1
            await progressHandler?(FileOperationProgress(currentItemName: plan.source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
        }

        return FileOperationResult(
            completedItems: completedItems,
            skippedItems: skippedItems,
            failedItems: failedItems,
            cleanupWarnings: cleanupWarnings,
            wasCancelled: false
        )
    }

    private func safelyCopy(source: URL, to destination: URL) throws -> [FileOperationCleanupWarning] {
        let tempURL = temporarySibling(for: destination, prefix: ".pulsefiles-copy")
        do {
            try fileManager.copyItem(at: source, to: tempURL)
            return try placeStagedItem(tempURL, at: destination)
        } catch {
            try? removeIfExists(tempURL)
            throw error
        }
    }

    private func safelyMove(
        source: URL,
        to destination: URL,
        replacingExistingDestination: Bool
    ) throws -> [FileOperationCleanupWarning] {
        guard replacingExistingDestination else {
            do {
                try fileManager.moveItem(at: source, to: destination)
                return []
            } catch {
                guard shouldFallbackToCopyDelete(forMoveError: error) else {
                    throw error
                }
                return try copyThenDeleteMove(source: source, to: destination)
            }
        }

        return try copyThenDeleteMove(source: source, to: destination)
    }

    private func copyThenDeleteMove(source: URL, to destination: URL) throws -> [FileOperationCleanupWarning] {
        let tempURL = temporarySibling(for: destination, prefix: ".pulsefiles-move")
        do {
            try fileManager.copyItem(at: source, to: tempURL)
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

        let backupURL = temporarySibling(for: destination, prefix: ".pulsefiles-backup")
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
            let normalizedSource = normalizedPath(source)
            guard normalizedSources.insert(normalizedSource).inserted else {
                throw FileOperationError.duplicateSource(source)
            }

            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try accessPolicy.validateAccess(to: destination)
            try validateDestination(destination, for: source)
            let normalizedDestination = normalizedPath(destination)
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
        if fileManager.fileExists(atPath: destination.path), normalizedPath(source) != normalizedPath(destination) {
            throw FileOperationError.destinationExists(destination)
        }
    }

    private func preflightDelete(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw FileOperationError.emptySelection }
        var normalizedSources = Set<String>()
        for url in urls {
            try accessPolicy.validateAccess(to: url)
            try validateExistingSource(url)
            guard normalizedSources.insert(normalizedPath(url)).inserted else {
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
        let sourcePath = normalizedPath(source)
        let destinationPath = normalizedPath(destination)
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
    }

    private func temporarySibling(for destination: URL, prefix: String) -> URL {
        destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)-\(destination.lastPathComponent)")
    }

    private func removeIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

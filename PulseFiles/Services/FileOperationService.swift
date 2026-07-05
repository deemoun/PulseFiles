import Foundation

enum FileOperationError: LocalizedError {
    case emptySelection
    case destinationInsideSource(source: URL, destination: URL)
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No files are selected."
        case .destinationInsideSource:
            return "Invalid destination."
        case .destinationExists(let url):
            return "\(url.lastPathComponent) already exists."
        }
    }

    var failureReason: String? {
        switch self {
        case .emptySelection:
            return "Select one or more items in the active pane."
        case .destinationInsideSource(let source, let destination):
            return "Cannot copy or move \(source.lastPathComponent) into \(destination.path)."
        case .destinationExists(let url):
            return "The destination already contains \(url.lastPathComponent)."
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

struct FileOperationResult {
    let completedItems: [URL]
    let skippedItems: [URL]
    let failedItems: [FileOperationItemFailure]
    let wasCancelled: Bool

    var succeededCompletely: Bool {
        !wasCancelled && skippedItems.isEmpty && failedItems.isEmpty
    }
}

typealias FileOperationProgressHandler = @MainActor (FileOperationProgress) -> Void
typealias FileConflictHandler = (URL) async -> FileConflictResolution

protocol FileOperationServicing {
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
}

final class FileOperationService: FileOperationServicing {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    func copy(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        try validateTransferRequest(request)
        return try await performTransfer(request, conflictHandler: conflictHandler, progressHandler: progressHandler) { fileManager, source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func move(
        _ request: FileOperationRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler? = nil
    ) async throws -> FileOperationResult {
        try validateTransferRequest(request)
        return try await performTransfer(request, conflictHandler: conflictHandler, progressHandler: progressHandler) { fileManager, source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            #if os(macOS)
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            #else
            throw CocoaError(.featureUnsupported)
            #endif
        }
    }

    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler? = nil) async throws -> FileOperationResult {
        try await performDelete(urls, progressHandler: progressHandler) { fileManager, url in
            try fileManager.removeItem(at: url)
        }
    }

    private func performDelete(
        _ urls: [URL],
        progressHandler: FileOperationProgressHandler?,
        operation: @escaping @Sendable (FileManager, URL) throws -> Void
    ) async throws -> FileOperationResult {
        guard !urls.isEmpty else { throw FileOperationError.emptySelection }
        for url in urls {
            try accessPolicy.validateAccess(to: url)
        }

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
                let fileManager = fileManager
                try await Task.detached(priority: .utility) {
                    try operation(fileManager, url)
                }.value
                completedItems.append(url)
            } catch is CancellationError {
                return FileOperationResult(completedItems: completedItems, skippedItems: [], failedItems: failedItems, wasCancelled: true)
            } catch {
                failedItems.append(FileOperationItemFailure(url: url, error: error))
            }
            completedCount += 1
            await progressHandler?(FileOperationProgress(currentItemName: url.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
        }

        return FileOperationResult(completedItems: completedItems, skippedItems: [], failedItems: failedItems, wasCancelled: false)
    }

    private func performTransfer(
        _ request: FileOperationRequest,
        conflictHandler: FileConflictHandler,
        progressHandler: FileOperationProgressHandler?,
        operation: @escaping @Sendable (FileManager, URL, URL) throws -> Void
    ) async throws -> FileOperationResult {
        var completedItems: [URL] = []
        var skippedItems: [URL] = []
        var failedItems: [FileOperationItemFailure] = []
        let totalCount = request.sources.count
        var completedCount = 0

        for source in request.sources {
            if Task.isCancelled {
                return FileOperationResult(completedItems: completedItems, skippedItems: skippedItems, failedItems: failedItems, wasCancelled: true)
            }

            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            do {
                try accessPolicy.validateAccess(to: source)
                try validateDestination(destination, for: source)
            } catch {
                failedItems.append(FileOperationItemFailure(url: source, error: error))
                completedCount += 1
                await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
                continue
            }
            switch try await resolveConflict(at: destination, conflictHandler: conflictHandler) {
            case .replace:
                do {
                    try await removeExistingItem(at: destination)
                } catch {
                    failedItems.append(FileOperationItemFailure(url: source, error: error))
                    completedCount += 1
                    continue
                }
            case .skip:
                skippedItems.append(source)
                completedCount += 1
                await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
                continue
            case .cancel:
                return FileOperationResult(completedItems: completedItems, skippedItems: skippedItems, failedItems: failedItems, wasCancelled: true)
            }

            await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
            do {
                let fileManager = fileManager
                try await Task.detached(priority: .utility) {
                    try operation(fileManager, source, destination)
                }.value
                completedItems.append(source)
            } catch is CancellationError {
                return FileOperationResult(completedItems: completedItems, skippedItems: skippedItems, failedItems: failedItems, wasCancelled: true)
            } catch {
                failedItems.append(FileOperationItemFailure(url: source, error: error))
            }
            completedCount += 1
            await progressHandler?(FileOperationProgress(currentItemName: source.lastPathComponent, completedCount: completedCount, totalCount: totalCount))
        }

        return FileOperationResult(completedItems: completedItems, skippedItems: skippedItems, failedItems: failedItems, wasCancelled: false)
    }

    private func validateTransferRequest(_ request: FileOperationRequest) throws {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        try accessPolicy.validateAccess(to: request.destinationDirectory)
    }

    private func validateDestination(_ destination: URL, for source: URL) throws {
        try accessPolicy.validateAccess(to: destination)
        let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
    }

    private func resolveConflict(at destination: URL, conflictHandler: FileConflictHandler) async throws -> FileConflictResolution {
        guard fileManager.fileExists(atPath: destination.path) else { return .replace }
        return await conflictHandler(destination)
    }

    private func removeExistingItem(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let fileManager = fileManager
        try await Task.detached(priority: .utility) {
            try fileManager.removeItem(at: url)
        }.value
    }
}

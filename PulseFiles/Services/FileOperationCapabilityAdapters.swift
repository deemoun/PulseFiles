import Foundation

/// Bridges archive operations into the file-operation facade while retaining
/// the same sandbox policy instance as every other mutation path.
final class FileOperationArchiveAdapter: FileOperationArchiveServicing {
    private let service: ArchiveOperationService

    init(accessPolicy: SandboxFileAccessPolicy) {
        service = ArchiveOperationService(accessPolicy: accessPolicy)
    }

    func createArchive(
        _ request: ArchiveCreateRequest,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> FileOperationResult {
        try await service.create(request, progressHandler: progressHandler)
    }

    func extractArchive(
        _ request: ArchiveExtractRequest,
        conflictHandler: @escaping FileConflictHandler,
        progressHandler: FileOperationProgressHandler?
    ) async throws -> FileOperationResult {
        try await service.extract(
            request,
            conflictHandler: conflictHandler,
            progressHandler: progressHandler
        )
    }
}

/// Bridges batch rename planning and execution into the facade. Keeping the
/// planner and executor together guarantees execution consumes a validated
/// plan produced under the shared sandbox boundary.
final class FileOperationBatchRenameAdapter: FileOperationBatchRenameServicing {
    private let service: BatchRenameService

    init(accessPolicy: SandboxFileAccessPolicy) {
        service = BatchRenameService(accessPolicy: accessPolicy)
    }

    func planBatchRename(_ request: BatchRenameRequest) throws -> BatchRenamePlan {
        try service.plan(request)
    }

    func batchRename(
        _ plan: BatchRenamePlan,
        progressHandler: FileOperationProgressHandler?
    ) async -> FileOperationResult {
        await service.execute(plan, progressHandler: progressHandler)
    }
}

/// Executes the common, cancellation-aware loop used by trash and permanent
/// delete. Validation and the descriptor-relative mutation remain injected by
/// the facade, so the executor cannot bypass either safety boundary.
struct FileOperationTrashDeleteExecutor {
    let fileManager: FileOperationFileManaging

    func execute(
        _ urls: [URL],
        progressHandler: FileOperationProgressHandler?,
        validate: (URL) throws -> Void,
        shouldStopAfterError: (Error) -> Bool,
        operation: (FileOperationFileManaging, URL) throws -> Void
    ) async -> FileOperationResult {
        var completedItems: [URL] = []
        var failedItems: [FileOperationItemFailure] = []
        var completedCount = 0

        for url in urls {
            if Task.isCancelled {
                DiagnosticLogger.log(.info, category: "FileOperation", "Delete operation cancelled: completedCount=\(completedItems.count); failedCount=\(failedItems.count)")
                return FileOperationResult(
                    completedItems: completedItems,
                    skippedItems: [],
                    failedItems: failedItems,
                    wasCancelled: true
                )
            }
            await progressHandler?(.init(
                currentItemName: url.lastPathComponent,
                completedCount: completedCount,
                totalCount: urls.count
            ))
            guard fileManager.fileExists(atPath: url.path) else {
                failedItems.append(.init(url: url, error: FileOperationError.sourceMissing(url)))
                break
            }
            do {
                try validate(url)
            } catch {
                failedItems.append(.init(url: url, error: error))
                break
            }
            do {
                try operation(fileManager, url)
                completedItems.append(url)
            } catch {
                DiagnosticLogger.log(.error, category: "FileOperation", "Item operation failed: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(error.localizedDescription)")
                failedItems.append(.init(url: url, error: error))
                if shouldStopAfterError(error) { break }
            }
            completedCount += 1
            await progressHandler?(.init(
                currentItemName: url.lastPathComponent,
                completedCount: completedCount,
                totalCount: urls.count
            ))
        }

        return .init(
            completedItems: completedItems,
            skippedItems: [],
            failedItems: failedItems,
            wasCancelled: false
        )
    }
}

/// Centralizes the conditions under which the facade publishes an undo plan.
/// Partial and identity-less operations intentionally produce no recovery.
struct FileOperationUndoPlanBuilder {
    func rename(from source: URL, to destination: URL) -> FileOperationRecovery {
        .init(kind: .rename, items: [.init(originalURL: source, destinationURL: destination)])
    }

    func move(_ pairs: [(source: URL, destination: URL)]) -> FileOperationRecovery {
        .init(kind: .move, items: pairs.map {
            .init(originalURL: $0.source, destinationURL: $0.destination)
        })
    }

    func copy(_ items: [FileOperationRecovery.Item]) -> FileOperationRecovery? {
        guard items.allSatisfy({ $0.destinationIdentity != nil }) else { return nil }
        return .init(kind: .copy, items: items)
    }

    func trash(_ items: [FileOperationRecovery.Item], expectedCount: Int) -> FileOperationRecovery? {
        guard items.count == expectedCount else { return nil }
        return .init(kind: .trash, items: items)
    }
}

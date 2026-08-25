import AppKit
import Foundation

/// AppKit presentation owned by the main window. The operation coordinator never
/// constructs alerts or windows, which keeps its orchestration directly testable.
@MainActor
protocol FileOperationPresenting: AnyObject {
    func presentFileOperationConfirmation(
        operationName: String,
        urls: [URL],
        destinationDirectory: URL?,
        confirmButtonTitle: String,
        completion: @escaping () -> Void
    )
    func resolveFileOperationConflict(destination: URL, operationName: String) async -> FileConflictResolution
    func beginFileOperationProgress(named operationName: String)
    func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String)
    func endFileOperationProgress()
    func showFileOperationCancellationPending()
    func presentFileOperationResult(_ result: FileOperationResult, operationName: String)
    func presentFileOperationError(operationName: String, detail: String)
    func presentUndoUnavailable()
    func presentDetachedFileOperationWarning()
}

/// Coordinates mutations which affect one or both panes. Pane selection and the
/// decision about which panes refresh remain callbacks owned by the application
/// coordination layer.
@MainActor
final class MainWindowFileOperationCoordinator {
    private let fileOperations: any FileOperationCoordinating
    private let state: FileOperationCoordinator
    private let accessPolicy: SandboxFileAccessPolicy
    private weak var presenter: (any FileOperationPresenting)?
    private let onActivityChanged: () -> Void
    private let onDefaultRefresh: () -> Void
    private let onResult: (String, FileOperationResult) -> Void
    private let onOperationStarted: () -> Void

    var isActive: Bool { state.isActive }
    var undoRecovery: FileOperationRecovery? { state.undoRecovery }

    init(
        fileOperations: any FileOperationCoordinating,
        state: FileOperationCoordinator,
        accessPolicy: SandboxFileAccessPolicy,
        presenter: any FileOperationPresenting,
        onActivityChanged: @escaping () -> Void,
        onDefaultRefresh: @escaping () -> Void,
        onResult: @escaping (String, FileOperationResult) -> Void,
        onOperationStarted: @escaping () -> Void
    ) {
        self.fileOperations = fileOperations
        self.state = state
        self.accessPolicy = accessPolicy
        self.presenter = presenter
        self.onActivityChanged = onActivityChanged
        self.onDefaultRefresh = onDefaultRefresh
        self.onResult = onResult
        self.onOperationStarted = onOperationStarted
    }

    func start(
        named operationName: String,
        captureRecovery: Bool = false,
        operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult,
        refresh: ((FileOperationResult) -> Void)? = nil,
        completion: ((FileOperationResult) -> Void)? = nil
    ) {
        guard let generation = state.begin() else { return }
        onActivityChanged()
        presenter?.beginFileOperationProgress(named: operationName)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.state.acceptsUpdates(for: generation) {
                    self.presenter?.endFileOperationProgress()
                    self.state.finish(generation: generation, result: nil, captureRecovery: false)
                    self.onActivityChanged()
                }
            }
            do {
                let result = try await state.runDetached {
                    try await operation { [weak self] progress in
                        guard let self, self.state.acceptsUpdates(for: generation) else { return }
                        self.presenter?.updateFileOperationProgress(progress, operationName: operationName)
                    }
                }
                guard state.acceptsUpdates(for: generation) else { return }
                if captureRecovery { state.captureRecovery(from: result) }
                onResult(operationName, result)
                onOperationStarted()
                if let refresh { refresh(result) } else { onDefaultRefresh() }
                completion?(result)
                presenter?.presentFileOperationResult(result, operationName: operationName)
            } catch {
                guard state.acceptsUpdates(for: generation) else { return }
                let localized = error as? LocalizedError
                presenter?.presentFileOperationError(operationName: operationName, detail: localized?.failureReason ?? error.localizedDescription)
            }
        }
        state.retain(task, for: generation)
    }

    func transfer(
        named operationName: String,
        sources: [URL],
        destinationDirectory: URL,
        shouldConfirm: Bool,
        captureRecovery: Bool = true,
        operation: @escaping (FileOperationRequest, @escaping FileConflictHandler, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) throws {
        for source in sources { try accessPolicy.validateAccess(to: source) }
        try accessPolicy.validateAccess(to: destinationDirectory)
        let request = try FileTransferWorkflowCoordinator.validatedRequest(sources: sources, destination: destinationDirectory)
        let begin = { [weak self] in
            guard let self else { return }
            self.start(named: operationName, captureRecovery: captureRecovery) { [weak self] progress in
                guard let self else { throw CancellationError() }
                return try await operation(request, { [weak self] destination in
                    guard let self else { return .cancel }
                    return await self.presenter?.resolveFileOperationConflict(destination: destination, operationName: operationName) ?? .cancel
                }, progress)
            }
        }
        if shouldConfirm {
            presenter?.presentFileOperationConfirmation(operationName: operationName, urls: sources, destinationDirectory: destinationDirectory, confirmButtonTitle: operationName, completion: begin)
        } else { begin() }
    }

    func undo() {
        guard let recovery = state.undoRecovery else {
            presenter?.presentUndoUnavailable()
            return
        }
        state.clearRecovery()
        start(named: recovery.undoTitle.localized) { [fileOperations] progress in
            try await fileOperations.undo(recovery, progressHandler: progress)
        }
    }

    func cancel() {
        guard state.isActive else { return }
        state.cancel()
        presenter?.showFileOperationCancellationPending()
    }

    func detach() {
        guard state.detach() != nil else { return }
        presenter?.endFileOperationProgress()
        onActivityChanged()
        onDefaultRefresh()
        presenter?.presentDetachedFileOperationWarning()
    }
}

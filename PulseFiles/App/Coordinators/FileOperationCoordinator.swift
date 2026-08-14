import AppKit
import Foundation

/// Owns workflow state, result presentation, cancellation and safe undo capture.
/// AppKit supplies progress/result closures and remains responsible for pane refresh.
@MainActor
final class FileOperationCoordinator {
    private(set) var activeTask: Task<Void, Never>?
    private var retainedTasks: [Int: Task<Void, Never>] = [:]
    private(set) var generation = 0
    private(set) var currentGeneration: Int?
    private(set) var undoRecovery: FileOperationRecovery?
    private(set) var isActive = false

    func captureRecovery(from result: FileOperationResult) {
        undoRecovery = result.succeededCompletely ? result.recovery : nil
    }

    func clearRecovery() { undoRecovery = nil }
    func cancel() { activeTask?.cancel() }

    @discardableResult
    func begin() -> Int? {
        guard !isActive else { return nil }
        generation += 1
        currentGeneration = generation
        isActive = true
        return generation
    }

    func retain(_ task: Task<Void, Never>, for generation: Int) {
        guard currentGeneration == generation else { return }
        activeTask = task
        retainedTasks[generation] = task
    }

    func acceptsUpdates(for generation: Int) -> Bool { currentGeneration == generation }

    /// The coordinator owns the detached worker boundary so cancellation and
    /// generation invalidation cannot drift apart from presentation state.
    func runDetached(_ operation: @escaping @Sendable () async throws -> FileOperationResult) async throws -> FileOperationResult {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    func finish(generation: Int, result: FileOperationResult?, captureRecovery: Bool) {
        retainedTasks[generation] = nil
        guard currentGeneration == generation else { return }
        if captureRecovery, let result { self.captureRecovery(from: result) }
        activeTask = nil
        currentGeneration = nil
        isActive = false
    }

    /// Releases presentation ownership while retaining the worker until it exits.
    func detach() -> Int? {
        guard let detached = currentGeneration else { return nil }
        activeTask?.cancel()
        generation += 1
        activeTask = nil
        currentGeneration = nil
        isActive = false
        undoRecovery = nil
        return detached
    }

    static func resultPresentation(_ result: FileOperationResult, operationName: String) -> (message: String, detail: String, style: NSAlert.Style)? {
        guard !result.succeededCompletely else { return nil }
        var details = [
            "Completed: %d".localized(with: result.completedItems.count),
            "Skipped: %d".localized(with: result.skippedItems.count),
            "Failed: %d".localized(with: result.failedItems.count),
            "Cleanup warnings: %d".localized(with: result.cleanupWarnings.count)
        ]
        if result.needsVerification { details.append("The operation's final filesystem state is unknown. Refresh and verify the affected items before continuing.".localized) }
        if result.wasCancelled { details.append("The whole operation was cancelled before all items completed.".localized) }
        if !result.failedItems.isEmpty { details.append("Partial failure: some selected items were not changed.".localized) }
        details.append(contentsOf: result.failedItems.map { "\($0.url.lastPathComponent): \($0.error.localizedDescription)" })
        details.append(contentsOf: result.cleanupWarnings.map { "\($0.url.lastPathComponent): \($0.message)" })
        let onlyCancelled = result.wasCancelled && !result.needsVerification && result.failedItems.isEmpty && result.cleanupWarnings.isEmpty
        let message = result.needsVerification ? "%@ Needs Verification".localized(with: operationName)
            : onlyCancelled ? "%@ Cancelled".localized(with: operationName)
            : "%@ Finished With Issues".localized(with: operationName)
        return (message, details.joined(separator: "\n"), onlyCancelled ? .informational : .warning)
    }
}

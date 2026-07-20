import Foundation

/// Keeps the pane's volume status responsive while volume resource values are read.
/// A result is accepted only for the directory and directory-load generation that
/// initiated it, preventing a slow previous volume from replacing current status.
@MainActor
final class VolumeStatusResolutionCache {
    private struct Request: Equatable {
        let directory: URL
        let loadGeneration: Int
    }

    private var task: Task<Void, Never>?
    private var request: Request?
    private(set) var status: VolumeStatusPresentation
    var onChange: (() -> Void)?

    init(directory: URL) {
        status = .loading(for: directory)
    }

    deinit {
        task?.cancel()
    }

    func resolveIfNeeded(for directory: URL, loadGeneration: Int) {
        let request = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        guard request != self.request else { return }
        beginResolution(for: directory, loadGeneration: loadGeneration)
        task = Task { [weak self] in
            let status = await VolumeStatusPresentation.resolve(for: directory)
            guard !Task.isCancelled else { return }
            self?.apply(status, for: directory, loadGeneration: loadGeneration)
        }
    }

    func beginResolution(for directory: URL, loadGeneration: Int) {
        task?.cancel()
        self.request = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        status = .loading(for: directory)
        onChange?()
    }

    /// Kept internal so XCTest can verify stale-result suppression without relying
    /// on timing-sensitive filesystem behavior.
    func apply(_ status: VolumeStatusPresentation, for directory: URL, loadGeneration: Int) {
        let completedRequest = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        guard completedRequest == request else { return }
        self.status = status
        task = nil
        onChange?()
    }
}

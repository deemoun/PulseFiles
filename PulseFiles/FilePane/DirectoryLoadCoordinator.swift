// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
import PulseFilesServices

package protocol DirectoryMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    func startMonitoring(_ url: URL)
    func stop()
}

extension DirectoryMonitor: DirectoryMonitoring {}

/// Owns the asynchronous lifetime of pane loads. All completion delivery is
/// generation checked, including implementations that ignore cancellation.
@MainActor
package final class DirectoryLoadCoordinator {
    package enum State {
        case idle
        case loading(generation: Int, directory: URL)
        case loaded(generation: Int, directory: URL)
        case failed(generation: Int, directory: URL, error: Error)
        case retryScheduled(generation: Int, directory: URL, attempt: Int)
    }

    package struct Request {
        let directory: URL
        let includeHidden: Bool
        let sort: FileSortDescriptor
        let forceRefresh: Bool
    }

    package private(set) var state: State = .idle
    package var generation: Int { nextGeneration }
    package var isLoading: Bool { if case .loading = state { return true }; return false }
    package var isRetryScheduled: Bool { if case .retryScheduled = state { return true }; return false }
    package var onMonitorChange: (() -> Void)?

    private let fileSystem: FileSystemServicing
    private let accessPolicy: any BrowseAccessPolicy
    private let snapshotCache: DirectorySnapshotCache
    private let monitor: any DirectoryMonitoring
    private let timeout: TimeInterval
    private var nextGeneration = 0
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var retry: Task<Void, Never>?

    package init(fileSystem: FileSystemServicing, accessPolicy: any BrowseAccessPolicy,
                 snapshotCache: DirectorySnapshotCache = DirectorySnapshotCache(),
                 monitor: any DirectoryMonitoring = DirectoryMonitor(), timeout: TimeInterval = 15) {
        precondition(timeout > 0 && timeout.isFinite)
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
        self.snapshotCache = snapshotCache
        self.monitor = monitor
        self.timeout = timeout
        monitor.onChange = { [weak self] in
            Task { @MainActor [weak self] in self?.onMonitorChange?() }
        }
    }

    deinit {
        task?.cancel()
        watchdog?.cancel()
        retry?.cancel()
        monitor.onChange = nil
        monitor.stop()
    }

    package func invalidate(_ directory: URL) { snapshotCache.invalidate(directory: directory) }
    package func clearCache() { snapshotCache.clear() }
    package func stopMonitoring() { monitor.stop() }
    package func monitor(_ directory: URL) { monitor.startMonitoring(directory) }
    package func cancel() {
        task?.cancel()
        watchdog?.cancel()
        retry?.cancel()
        task = nil
        watchdog = nil
        retry = nil
        state = .idle
    }

    package func load(_ request: Request, completion: @escaping (Int, Result<DirectoryContentsResult, Error>) -> Void) {
        cancel()
        nextGeneration += 1
        let generation = nextGeneration
        state = .loading(generation: generation, directory: request.directory)
        let fs = fileSystem, policy = accessPolicy, cache = snapshotCache
        watchdog = Task { [weak self] in
            guard let timeout = self?.timeout else { return }
            do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
            guard let self, self.isCurrent(generation) else { return }
            self.task?.cancel(); self.task = nil
            let error = DirectoryLoadTimeoutError(timeout: self.timeout)
            self.state = .failed(generation: generation, directory: request.directory, error: error)
            completion(generation, .failure(error))
        }
        task = Task { [weak self] in
            do {
                let key = DirectorySnapshotCache.Key(directory: request.directory, includesHiddenFiles: request.includeHidden, sort: request.sort)
                let result: DirectoryContentsResult
                if !request.forceRefresh, let snapshot = cache.snapshot(for: key),
                   snapshot.metadata == (try await policy.withValidatedAccess(to: request.directory) { try await fs.directorySnapshotMetadata(at: request.directory) }) {
                    result = .init(items: snapshot.items, itemReadFailures: [])
                } else {
                    result = try await policy.withValidatedAccess(to: request.directory) { try await fs.contentsOfDirectory(at: request.directory, includingHidden: request.includeHidden, sort: request.sort) }
                    if result.isComplete {
                        let metadata = try await policy.withValidatedAccess(to: request.directory) { try await fs.directorySnapshotMetadata(at: request.directory) }
                        cache.store(result.items, metadata: metadata, for: key)
                    }
                }
                guard !Task.isCancelled, let self, self.isCurrent(generation) else { return }
                self.watchdog?.cancel(); self.watchdog = nil; self.task = nil
                self.state = .loaded(generation: generation, directory: request.directory)
                completion(generation, .success(result))
            } catch {
                guard !(error is CancellationError), let self, self.isCurrent(generation) else { return }
                self.watchdog?.cancel(); self.watchdog = nil; self.task = nil
                self.state = .failed(generation: generation, directory: request.directory, error: error)
                completion(generation, .failure(error))
            }
        }
    }

    package func scheduleRetry(directory: URL, attempt: Int, action: @escaping () -> Void) {
        retry?.cancel()
        let generation = nextGeneration
        state = .retryScheduled(generation: generation, directory: directory, attempt: attempt)
        retry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self, case .retryScheduled(let current, let url, _) = self.state,
                  current == generation, url == directory else { return }
            self.retry = nil; action()
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        if case .loading(let current, _) = state { return current == generation }
        return false
    }
}

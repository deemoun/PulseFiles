import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// A short, cancellable read-only filesystem query.  A missing answer means the
/// filesystem did not respond before the caller's UI deadline; it is not treated
/// as a positive result.
package enum FileSystemProbeAnswer<Value: Sendable>: Sendable, Equatable where Value: Equatable {
    case value(Value)
    case unavailable
}

package protocol FileSystemProbing: Sendable {
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?>
}

/// Keeps potentially blocking FileManager and resource-value queries off the
/// main actor. Network volumes occasionally block these APIs, so callers always
/// supply a small deadline and treat `.unavailable` conservatively.
package final class FileSystemProbeService: FileSystemProbing, @unchecked Sendable {
    private let existsOperation: @Sendable (URL) -> Bool
    private let directoryOperation: @Sendable (URL) -> Bool
    private let volumeOperation: @Sendable (URL) -> String?
    private let scheduler: FileSystemOperationScheduler

    package init(fileManager: FileManager = .default, scheduler: FileSystemOperationScheduler = .shared) {
        self.scheduler = scheduler
        let operations = FileManagerProbeOperations(fileManager: fileManager)
        existsOperation = { operations.exists(at: $0) }
        directoryOperation = { operations.isDirectory(at: $0) }
        volumeOperation = { url in
            let values = try? url.resourceValues(forKeys: [.volumeURLKey])
            return (values?.allValues[.volumeURLKey] as? URL)?.standardizedFileURL.path
        }
    }

    package init(
        existsOperation: @escaping @Sendable (URL) -> Bool,
        directoryOperation: @escaping @Sendable (URL) -> Bool,
        volumeOperation: @escaping @Sendable (URL) -> String?,
        scheduler: FileSystemOperationScheduler = .shared
    ) {
        self.scheduler = scheduler
        self.existsOperation = existsOperation
        self.directoryOperation = directoryOperation
        self.volumeOperation = volumeOperation
    }

    package func exists(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<Bool> {
        await query(deadline: deadline) { [existsOperation] in .value(existsOperation(url)) }
    }

    package func isDirectory(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<Bool> {
        await query(deadline: deadline) { [directoryOperation] in .value(directoryOperation(url)) }
    }

    package func volumeIdentifier(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<String?> {
        await query(deadline: deadline) { [volumeOperation] in .value(volumeOperation(url)) }
    }

    private func query<Value: Sendable & Equatable>(deadline: Duration, operation: @escaping @Sendable () -> FileSystemProbeAnswer<Value>) async -> FileSystemProbeAnswer<Value> {
        let cancellation = ProbeCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let completion = ProbeCompletion(continuation)
                let operationTask = Task {
                    do {
                        completion.finish(try await self.scheduler.submit(priority: .probe, operation: operation))
                    } catch {
                        completion.finish(.unavailable)
                    }
                }
                cancellation.set {
                    operationTask.cancel()
                    completion.finish(.unavailable)
                }
                Task.detached {
                    try? await Task.sleep(for: deadline)
                    operationTask.cancel()
                    completion.finish(.unavailable)
                }
            }
        } onCancel: {
            // The detached FileManager call may be uninterruptible, but the UI
            // caller stops awaiting it immediately.
            cancellation.cancel()
        }
    }
}

/// `FileManager` is not annotated as `Sendable`, although these read-only
/// queries are used concurrently by the probe scheduler. This wrapper keeps
/// that interoperability boundary explicit rather than capturing FileManager
/// directly in the scheduler's `@Sendable` closures.
private final class FileManagerProbeOperations: @unchecked Sendable {
    private let fileManager: FileManager

    package init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    package func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    package func isDirectory(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?
    private var wasCancelled = false

    package func set(_ cancellation: @escaping () -> Void) {
        lock.lock()
        if wasCancelled {
            lock.unlock()
            cancellation()
            return
        }
        self.cancellation = cancellation
        lock.unlock()
    }

    package func cancel() {
        lock.lock()
        wasCancelled = true
        let cancellation = self.cancellation
        self.cancellation = nil
        lock.unlock()
        cancellation?()
    }
}

private final class ProbeCompletion<Value: Sendable & Equatable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<FileSystemProbeAnswer<Value>, Never>?

    package init(_ continuation: CheckedContinuation<FileSystemProbeAnswer<Value>, Never>) {
        self.continuation = continuation
    }

    package func finish(_ value: FileSystemProbeAnswer<Value>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

// A small main-actor cache lets synchronous AppKit drag callbacks avoid touching
// a possibly unavailable filesystem. Unknown entries are explicitly pending.
@MainActor
package final class FileSystemProbeCache {
    private var existence: [URL: FileSystemProbeAnswer<Bool>] = [:]
    private var directories: [URL: FileSystemProbeAnswer<Bool>] = [:]
    private var volumes: [URL: FileSystemProbeAnswer<String?>] = [:]
    private let probe: any FileSystemProbing
    private let deadline: Duration

    package init(probe: any FileSystemProbing = FileSystemProbeService(), deadline: Duration = .milliseconds(150)) {
        self.probe = probe
        self.deadline = deadline
    }

    package func directoryValue(for url: URL) -> Bool? { value(directories[url]) }
    package func volumeIdentifier(for url: URL) -> String? { value(volumes[url]) ?? nil }
    package func hasVolumeIdentifierAnswer(for url: URL) -> Bool { volumes[url] != nil }

    package func requestDirectory(_ url: URL) {
        guard directories[url] == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.probe.isDirectory(url, deadline: self.deadline)
            guard !Task.isCancelled else { return }
            self.directories[url] = result
        }
    }

    package func requestVolumeIdentifier(_ url: URL) {
        guard volumes[url] == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.probe.volumeIdentifier(url, deadline: self.deadline)
            guard !Task.isCancelled else { return }
            self.volumes[url] = result
        }
    }

    private func value<T>(_ answer: FileSystemProbeAnswer<T>?) -> T? where T: Sendable & Equatable {
        guard case .value(let value) = answer else { return nil }
        return value
    }
}

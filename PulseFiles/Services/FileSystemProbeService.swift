import Foundation

/// A short, cancellable read-only filesystem query.  A missing answer means the
/// filesystem did not respond before the caller's UI deadline; it is not treated
/// as a positive result.
enum FileSystemProbeAnswer<Value: Sendable>: Sendable, Equatable where Value: Equatable {
    case value(Value)
    case unavailable
}

protocol FileSystemProbing: Sendable {
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?>
}

/// Keeps potentially blocking FileManager and resource-value queries off the
/// main actor. Network volumes occasionally block these APIs, so callers always
/// supply a small deadline and treat `.unavailable` conservatively.
final class FileSystemProbeService: FileSystemProbing, @unchecked Sendable {
    private let existsOperation: @Sendable (URL) -> Bool
    private let directoryOperation: @Sendable (URL) -> Bool
    private let volumeOperation: @Sendable (URL) -> String?

    init(fileManager: FileManager = .default) {
        existsOperation = { fileManager.fileExists(atPath: $0.path) }
        directoryOperation = { url in
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        volumeOperation = { url in
            let values = try? url.resourceValues(forKeys: [.volumeURLKey])
            return (values?.allValues[.volumeURLKey] as? URL)?.standardizedFileURL.path
        }
    }

    init(
        existsOperation: @escaping @Sendable (URL) -> Bool,
        directoryOperation: @escaping @Sendable (URL) -> Bool,
        volumeOperation: @escaping @Sendable (URL) -> String?
    ) {
        self.existsOperation = existsOperation
        self.directoryOperation = directoryOperation
        self.volumeOperation = volumeOperation
    }

    func exists(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<Bool> {
        await query(deadline: deadline) { [existsOperation] in .value(existsOperation(url)) }
    }

    func isDirectory(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<Bool> {
        await query(deadline: deadline) { [directoryOperation] in .value(directoryOperation(url)) }
    }

    func volumeIdentifier(_ url: URL, deadline: Duration = .milliseconds(250)) async -> FileSystemProbeAnswer<String?> {
        await query(deadline: deadline) { [volumeOperation] in .value(volumeOperation(url)) }
    }

    private func query<Value: Sendable & Equatable>(deadline: Duration, operation: @escaping @Sendable () -> FileSystemProbeAnswer<Value>) async -> FileSystemProbeAnswer<Value> {
        let cancellation = ProbeCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let completion = ProbeCompletion(continuation)
                cancellation.set { completion.finish(.unavailable) }
                Task.detached(priority: .utility) { completion.finish(operation()) }
                Task.detached {
                    try? await Task.sleep(for: deadline)
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

private final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?
    private var wasCancelled = false

    func set(_ cancellation: @escaping () -> Void) {
        lock.lock()
        if wasCancelled {
            lock.unlock()
            cancellation()
            return
        }
        self.cancellation = cancellation
        lock.unlock()
    }

    func cancel() {
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

    init(_ continuation: CheckedContinuation<FileSystemProbeAnswer<Value>, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: FileSystemProbeAnswer<Value>) {
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
final class FileSystemProbeCache {
    private var existence: [URL: FileSystemProbeAnswer<Bool>] = [:]
    private var directories: [URL: FileSystemProbeAnswer<Bool>] = [:]
    private var volumes: [URL: FileSystemProbeAnswer<String?>] = [:]
    private let probe: any FileSystemProbing
    private let deadline: Duration

    init(probe: any FileSystemProbing = FileSystemProbeService(), deadline: Duration = .milliseconds(150)) {
        self.probe = probe
        self.deadline = deadline
    }

    func directoryValue(for url: URL) -> Bool? { value(directories[url]) }
    func volumeIdentifier(for url: URL) -> String? { value(volumes[url]) ?? nil }
    func hasVolumeIdentifierAnswer(for url: URL) -> Bool { volumes[url] != nil }

    func requestDirectory(_ url: URL) {
        guard directories[url] == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.probe.isDirectory(url, deadline: self.deadline)
            guard !Task.isCancelled else { return }
            self.directories[url] = result
        }
    }

    func requestVolumeIdentifier(_ url: URL) {
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

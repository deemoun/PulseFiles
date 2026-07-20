import Foundation
import Darwin

protocol DirectoryMonitorSource: AnyObject {
    func setEventHandler(_ handler: @escaping () -> Void)
    func setCancelHandler(_ handler: @escaping () -> Void)
    func resume()
    func cancel()
}

struct DirectoryMonitorSourceHandle {
    let fileDescriptor: CInt
    let source: DirectoryMonitorSource
}

protocol DirectoryMonitorSourceFactory {
    func makeSource(for url: URL, queue: DispatchQueue) -> DirectoryMonitorSourceHandle?
}

protocol DirectoryMonitorDebounceWork: AnyObject {
    func cancel()
}

protocol DirectoryMonitorDebounceScheduling {
    func schedule(after delay: DispatchTimeInterval, on queue: DispatchQueue, _ action: @escaping () -> Void) -> DirectoryMonitorDebounceWork
}

private final class DispatchDirectoryMonitorSource: DirectoryMonitorSource {
    private let source: DispatchSourceFileSystemObject

    init(source: DispatchSourceFileSystemObject) {
        self.source = source
    }

    func setEventHandler(_ handler: @escaping () -> Void) { source.setEventHandler(handler: handler) }
    func setCancelHandler(_ handler: @escaping () -> Void) { source.setCancelHandler(handler: handler) }
    func resume() { source.resume() }
    func cancel() { source.cancel() }
}

private struct SystemDirectoryMonitorSourceFactory: DirectoryMonitorSourceFactory {
    func makeSource(for url: URL, queue: DispatchQueue) -> DirectoryMonitorSourceHandle? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke, .attrib, .extend],
            queue: queue
        )
        source.setCancelHandler { close(descriptor) }
        return DirectoryMonitorSourceHandle(fileDescriptor: descriptor, source: DispatchDirectoryMonitorSource(source: source))
    }
}

private final class DispatchDirectoryMonitorDebounceWork: DirectoryMonitorDebounceWork {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) { self.workItem = workItem }
    func cancel() { workItem.cancel() }
}

private struct DispatchDirectoryMonitorDebounceScheduler: DirectoryMonitorDebounceScheduling {
    func schedule(after delay: DispatchTimeInterval, on queue: DispatchQueue, _ action: @escaping () -> Void) -> DirectoryMonitorDebounceWork {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchDirectoryMonitorDebounceWork(workItem: workItem)
    }
}

final class DirectoryMonitor {
    var onChange: (() -> Void)? {
        get { withState { onChangeHandler } }
        set { withState { onChangeHandler = newValue } }
    }

    // These members are accessed only from stateQueue. Keeping the descriptor and
    // source together prevents an old source's cancellation from affecting a new one.
    private var monitoredURL: URL?
    private var fileDescriptor: CInt = -1
    private var source: DirectoryMonitorSource?
    private var debounceWorkItem: DirectoryMonitorDebounceWork?
    private var generation = 0
    private var debounceGeneration = 0
    private var onChangeHandler: (() -> Void)?

    private let stateQueue: DispatchQueue
    private let queueIdentity = UUID()
    private let sourceFactory: DirectoryMonitorSourceFactory
    private let debounceScheduler: DirectoryMonitorDebounceScheduling

    init(
        sourceFactory: DirectoryMonitorSourceFactory = SystemDirectoryMonitorSourceFactory(),
        debounceScheduler: DirectoryMonitorDebounceScheduling = DispatchDirectoryMonitorDebounceScheduler(),
        queue: DispatchQueue? = nil
    ) {
        stateQueue = queue ?? DispatchQueue(label: "com.pulsefiles.directory-monitor", qos: .utility)
        self.sourceFactory = sourceFactory
        self.debounceScheduler = debounceScheduler
        stateQueue.setSpecific(key: queueSpecificKey, value: queueIdentity)
    }

    func startMonitoring(_ url: URL) {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        withState {
            guard monitoredURL != normalizedURL || source == nil else { return }
            stopLocked()

            monitoredURL = normalizedURL
            let monitorGeneration = generation
            guard let handle = sourceFactory.makeSource(for: normalizedURL, queue: stateQueue) else { return }

            fileDescriptor = handle.fileDescriptor
            handle.source.setEventHandler { [weak self] in
                self?.handleEvent(for: monitorGeneration)
            }
            source = handle.source
            handle.source.resume()
        }
    }

    func stop() {
        // Synchronous serialization also establishes an ordering with queued event
        // handlers and invalidates callbacks already waiting on the main queue.
        withState { stopLocked() }
    }

    private func stopLocked() {
        generation &+= 1
        debounceGeneration &+= 1
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        monitoredURL = nil

        fileDescriptor = -1
        let oldSource = source
        source = nil
        oldSource?.cancel()
        // The native source's cancel handler closes its captured descriptor. The
        // state field was cleared above, before cancellation can run asynchronously.
    }

    private func handleEvent(for eventGeneration: Int) {
        withState {
            guard eventGeneration == generation, source != nil else { return }
            debounceWorkItem?.cancel()
            debounceGeneration &+= 1
            let eventDebounceGeneration = debounceGeneration
            debounceWorkItem = debounceScheduler.schedule(after: .milliseconds(150), on: stateQueue) { [weak self] in
                self?.deliverChangeIfCurrent(generation: eventGeneration, debounceGeneration: eventDebounceGeneration)
            }
        }
    }

    private func deliverChangeIfCurrent(generation callbackGeneration: Int, debounceGeneration callbackDebounceGeneration: Int) {
        let handler = withState { () -> (() -> Void)? in
            guard callbackGeneration == generation,
                  callbackDebounceGeneration == debounceGeneration,
                  source != nil else { return nil }
            debounceWorkItem = nil
            return onChangeHandler
        }
        guard let handler else { return }
        DispatchQueue.main.async {
            // Recheck after the main-queue hop: stop/start may have happened while
            // this notification was pending.
            guard self.withState({
                callbackGeneration == self.generation
                    && callbackDebounceGeneration == self.debounceGeneration
                    && self.source != nil
            }) else { return }
            handler()
        }
    }

    private func withState<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueIdentity {
            return body()
        }
        return stateQueue.sync(execute: body)
    }

    deinit { stop() }
}

private let queueSpecificKey = DispatchSpecificKey<UUID>()

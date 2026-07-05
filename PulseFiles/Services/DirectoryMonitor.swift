import Foundation

final class DirectoryMonitor {
    var onChange: (() -> Void)?
    private var monitoredURL: URL?
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.pulsefiles.directory-monitor", qos: .utility)

    func startMonitoring(_ url: URL) {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if monitoredURL == normalizedURL, source != nil {
            return
        }

        stop()
        monitoredURL = normalizedURL
        fileDescriptor = open(normalizedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            fileDescriptor = -1
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChangeNotification()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        monitoredURL = nil
        if let source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func scheduleChangeNotification() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: workItem)
    }

    deinit {
        stop()
    }
}

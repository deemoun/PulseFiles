import Foundation

final class DirectoryMonitor {
    var onChange: (() -> Void)?

    func startMonitoring(_ url: URL) {
        // Phase 2 will replace this placeholder with debounced DispatchSource monitoring.
    }

    func stop() {}
}

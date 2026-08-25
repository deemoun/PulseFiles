import AppKit

/// Owns the lifecycle of independently presented, read-only viewer windows.
/// The main window only routes the focused file into this coordinator.
@MainActor
final class ReadOnlyViewerPresentationCoordinator {
    private let service: any ViewerContentLoading
    private var windowControllers: [NSWindowController] = []

    init(service: any ViewerContentLoading) { self.service = service }

    func present(_ url: URL, sender: Any? = nil) {
        let viewer = FileViewerViewController(url: url, service: service)
        let window = NSWindow(contentViewController: viewer)
        window.title = url.lastPathComponent
        window.setContentSize(NSSize(width: 820, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let controller = NSWindowController(window: window)
        windowControllers.removeAll { $0.window == nil }
        windowControllers.append(controller)
        controller.showWindow(sender)
        window.makeKeyAndOrderFront(sender)
    }

    var retainedWindowCountForTesting: Int {
        windowControllers.removeAll { $0.window == nil }
        return windowControllers.count
    }
}

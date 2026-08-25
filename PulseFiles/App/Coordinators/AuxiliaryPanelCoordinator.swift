import AppKit

@MainActor
final class AuxiliaryPresentationCoordinator: NSObject, NSWindowDelegate {
    private(set) var settingsWindowController: NSWindowController?
    private(set) var debugLogWindowController: NSWindowController?
    var onWindowClosed: (() -> Void)?

    func showSettings(_ controller: NSViewController, sender: Any?) {
        if let window = settingsWindowController?.window, window.isVisible { window.makeKeyAndOrderFront(sender); return }
        settingsWindowController = show(controller, title: "Settings".localized, size: NSSize(width: 760, height: 620), sender: sender)
    }

    func showDebugLogs(_ controller: NSViewController, sender: Any?) {
        if let window = debugLogWindowController?.window, window.isVisible { window.makeKeyAndOrderFront(sender); return }
        debugLogWindowController = show(controller, title: "Debug Logs".localized, size: NSSize(width: 900, height: 560), sender: sender)
    }

    private func show(_ controller: NSViewController, title: String, size: NSSize, sender: Any?) -> NSWindowController {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.setContentSize(size)
        window.delegate = self
        let owner = NSWindowController(window: window)
        owner.showWindow(sender)
        window.makeKeyAndOrderFront(sender)
        return owner
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindowController?.window { settingsWindowController = nil }
        if window === debugLogWindowController?.window { debugLogWindowController = nil }
        onWindowClosed?()
    }
}

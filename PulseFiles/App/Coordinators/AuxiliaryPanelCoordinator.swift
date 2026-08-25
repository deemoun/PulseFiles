import AppKit

@MainActor
final class AuxiliaryPresentationCoordinator: NSObject, NSWindowDelegate {
    private(set) var settingsWindowController: NSWindowController?
    private(set) var debugLogWindowController: NSWindowController?
    private var quickLocationsPopover: NSPopover?
    private var patternSelectionPanelController: PatternSelectionPanelController?
    var onWindowClosed: (() -> Void)?

    func showSettings(_ controller: NSViewController, sender: Any?) {
        if let window = settingsWindowController?.window, window.isVisible { window.makeKeyAndOrderFront(sender); return }
        settingsWindowController = show(controller, title: "Settings".localized, size: NSSize(width: 760, height: 620), sender: sender)
    }

    func showDebugLogs(_ controller: NSViewController, sender: Any?) {
        if let window = debugLogWindowController?.window, window.isVisible { window.makeKeyAndOrderFront(sender); return }
        debugLogWindowController = show(controller, title: "Debug Logs".localized, size: NSSize(width: 900, height: 560), sender: sender)
    }

    @discardableResult
    func showQuickLocations(_ controller: NSViewController, relativeTo positioningView: NSView) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        quickLocationsPopover = popover
        popover.show(relativeTo: positioningView.bounds, of: positioningView, preferredEdge: .maxY)
        return popover
    }

    func showPatternSelection(_ controller: PatternSelectionPanelController, window: NSWindow?, onClose: @escaping () -> Void) {
        controller.onClose = { [weak self, weak controller] in
            guard self?.patternSelectionPanelController === controller else { return }
            self?.patternSelectionPanelController = nil
            onClose()
        }
        patternSelectionPanelController = controller
        guard let panel = controller.window else { return }
        if let window { window.beginSheet(panel) } else { controller.showWindow(nil) }
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

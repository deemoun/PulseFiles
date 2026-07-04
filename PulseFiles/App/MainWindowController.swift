import AppKit

final class MainWindowController: NSWindowController {
    init() {
        let content = MainWindowViewController()
        let window = NSWindow(contentViewController: content)
        window.title = "PulseFiles"
        window.setFrame(NSRect(x: 120, y: 120, width: 1280, height: 820), display: false)
        window.minSize = NSSize(width: 920, height: 560)
        window.backgroundColor = LiquidGlassStyle.windowBackground
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.toolbar = PulseToolbar(owner: content)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class PulseToolbar: NSToolbar {
    init(owner: MainWindowViewController) {
        super.init(identifier: "PulseFilesToolbar")
        delegate = owner
        displayMode = .iconOnly
        allowsUserCustomization = false
    }
}

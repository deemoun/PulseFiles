import AppKit

/// Activates its pane without taking selection or navigation ownership from the pane controller.
final class PaneContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

import AppKit

/// Activates its pane without taking selection or navigation ownership from the pane controller.
package final class PaneContainerView: NSView {
    package var onMouseDown: (() -> Void)?

    package override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

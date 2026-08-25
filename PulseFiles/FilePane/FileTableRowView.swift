import AppKit

package final class FileTableRowView: NSTableRowView {
    package var drawsActiveSelection = true
    package var drawsKeyboardFocus = false

    package override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard drawsKeyboardFocus else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 3), xRadius: 7, yRadius: 7)
        path.lineWidth = 2
        NSColor.keyboardFocusIndicatorColor.setStroke()
        path.stroke()
    }

    package override func drawSelection(in dirtyRect: NSRect) {
        guard drawsActiveSelection else { return }
        let rect = bounds.insetBy(dx: 8, dy: 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.systemBlue.withAlphaComponent(0.55).setFill()
        path.fill()
    }
}

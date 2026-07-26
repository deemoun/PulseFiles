import AppKit

final class FileTableRowView: NSTableRowView {
    var drawsActiveSelection = true
    var drawsKeyboardFocus = false

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard drawsKeyboardFocus else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 3), xRadius: 7, yRadius: 7)
        path.lineWidth = 2
        NSColor.keyboardFocusIndicatorColor.setStroke()
        path.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard drawsActiveSelection else { return }
        let rect = bounds.insetBy(dx: 8, dy: 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.systemBlue.withAlphaComponent(0.55).setFill()
        path.fill()
    }
}

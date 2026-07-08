import AppKit

final class FileTableRowView: NSTableRowView {
    var drawsActiveSelection = true

    override func drawSelection(in dirtyRect: NSRect) {
        guard drawsActiveSelection else { return }
        let rect = bounds.insetBy(dx: 8, dy: 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.systemBlue.withAlphaComponent(0.55).setFill()
        path.fill()
    }
}

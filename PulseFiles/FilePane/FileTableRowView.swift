import AppKit

final class FileTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.75).setFill()
        dirtyRect.fill()
    }
}

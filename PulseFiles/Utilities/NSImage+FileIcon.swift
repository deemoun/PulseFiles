import AppKit
import Foundation

extension NSImage {
    static func fileIcon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

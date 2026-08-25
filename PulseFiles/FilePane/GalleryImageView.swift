import AppKit

/// Image view whose represented URL prevents recycled gallery cells from displaying stale thumbnails.
package final class GalleryImageView: NSImageView {
    package var representedURL: URL?
}

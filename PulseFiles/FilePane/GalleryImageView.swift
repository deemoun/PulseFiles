import AppKit

/// Image view whose represented URL prevents recycled gallery cells from displaying stale thumbnails.
final class GalleryImageView: NSImageView {
    var representedURL: URL?
}

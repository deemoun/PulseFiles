import AppKit

/// Resolves generic file icons on the main/AppKit context and retains only a
/// bounded set of images. Directory scanning therefore never invokes AppKit
/// once for each path.
@MainActor
final class FileIconProvider {
    static let shared = FileIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let imageResolver: (FileIconKey) -> NSImage

    init(countLimit: Int = 128, imageResolver: @escaping (FileIconKey) -> NSImage = FileIconProvider.defaultImage) {
        cache.countLimit = countLimit
        self.imageResolver = imageResolver
    }

    func image(for key: FileIconKey) -> NSImage {
        let cacheKey = key.cacheKey
        if let image = cache.object(forKey: cacheKey) {
            return image
        }

        let image = imageResolver(key)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Call this only when icon-related resource metadata has changed. A new
    /// `FileIconKey` naturally selects a different cached image.
    func invalidate(_ key: FileIconKey) {
        cache.removeObject(forKey: key.cacheKey)
    }

    private static func defaultImage(for key: FileIconKey) -> NSImage {
        switch key.fileType {
        case .folder:
            return NSImage(named: NSImage.folderName) ?? NSWorkspace.shared.icon(forFileType: "folder")
        case .symbolicLink:
            return NSWorkspace.shared.icon(forFileType: "alias")
        case .package:
            return workspaceIcon(fileType: key.fileExtension, fallback: "package")
        case .file, .unknown:
            return workspaceIcon(fileType: key.fileExtension, fallback: key.contentTypeIdentifier)
        }
    }

    private static func workspaceIcon(fileType: String, fallback: String?) -> NSImage {
        let resolvedType = fileType.isEmpty ? (fallback ?? "") : fileType
        guard !resolvedType.isEmpty else {
            return NSImage(named: NSImage.multipleDocumentsName) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFileType: resolvedType)
    }
}

private extension FileIconKey {
    var cacheKey: NSString {
        "\(fileType.rawValue)|\(fileExtension)|\(contentTypeIdentifier ?? "")|\(isAlias)" as NSString
    }
}

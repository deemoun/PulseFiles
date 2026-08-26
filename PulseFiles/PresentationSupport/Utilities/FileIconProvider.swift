// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesModels
import UniformTypeIdentifiers

/// Resolves generic file icons on the main/AppKit context and retains only a
/// bounded set of images. Directory scanning therefore never invokes AppKit
/// once for each path.
@MainActor
package final class FileIconProvider {
    package static let shared = FileIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let imageResolver: (FileIconKey) -> NSImage

    package init(countLimit: Int = 128, imageResolver: ((FileIconKey) -> NSImage)? = nil) {
        cache.countLimit = countLimit
        self.imageResolver = imageResolver ?? Self.defaultImage
    }

    package func image(for key: FileIconKey) -> NSImage {
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
    package func invalidate(_ key: FileIconKey) {
        cache.removeObject(forKey: key.cacheKey)
    }

    private static func defaultImage(for key: FileIconKey) -> NSImage {
        switch key.fileType {
        case .folder:
            return NSImage(named: NSImage.folderName) ?? NSWorkspace.shared.icon(for: .folder)
        case .symbolicLink:
            return NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil) ?? NSImage()
        case .package:
            return workspaceIcon(fileType: key.fileExtension, fallback: .package)
        case .file, .unknown:
            return workspaceIcon(fileType: key.fileExtension, fallback: key.contentTypeIdentifier)
        }
    }

    private static func workspaceIcon(fileType: String, fallback: String?) -> NSImage {
        let contentType = UTType(filenameExtension: fileType)
            ?? fallback.flatMap(UTType.init)
        guard let contentType else {
            return NSImage(named: NSImage.multipleDocumentsName) ?? NSImage()
        }
        return NSWorkspace.shared.icon(for: contentType)
    }

    private static func workspaceIcon(fileType: String, fallback: UTType) -> NSImage {
        let contentType = UTType(filenameExtension: fileType) ?? fallback
        return NSWorkspace.shared.icon(for: contentType)
    }
}

private extension FileIconKey {
    var cacheKey: NSString {
        "\(fileType.rawValue)|\(fileExtension)|\(contentTypeIdentifier ?? "")|\(isAlias)" as NSString
    }
}

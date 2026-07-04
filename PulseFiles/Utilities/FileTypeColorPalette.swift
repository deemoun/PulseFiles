import AppKit

enum FileTypeColorPalette {
    static let folder = NSColor.systemCyan
    static let symbolicLink = NSColor.systemPurple
    static let package = NSColor.systemGreen
    static let hidden = NSColor.secondaryLabelColor
    static let executable = NSColor.systemGreen
    static let archive = NSColor.systemOrange
    static let image = NSColor.systemTeal
    static let text = LiquidGlassStyle.label
    static let fallback = LiquidGlassStyle.label

    private static let executableMask = 0o111
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "xz", "zip"
    ]
    private static let imageExtensions: Set<String> = [
        "gif", "heic", "jpeg", "jpg", "png", "tiff", "webp"
    ]
    private static let textExtensions: Set<String> = [
        "css", "html", "js", "json", "md", "swift", "ts", "txt", "xml", "yaml", "yml"
    ]

    static func textColor(for item: FileItem) -> NSColor {
        if item.isDirectory || item.fileType == .folder {
            return folder
        }

        if item.isSymbolicLink || item.fileType == .symbolicLink {
            return symbolicLink
        }

        if item.fileType == .package {
            return package
        }

        if item.isHidden {
            return hidden
        }

        if isExecutable(item) {
            return executable
        }

        let fileExtension = item.fileExtension.lowercased()
        if archiveExtensions.contains(fileExtension) {
            return archive
        }

        if imageExtensions.contains(fileExtension) {
            return image
        }

        if textExtensions.contains(fileExtension) {
            return text
        }

        return fallback
    }

    private static func isExecutable(_ item: FileItem) -> Bool {
        guard let permissions = item.posixPermissions else { return false }
        return permissions & executableMask != 0
    }
}

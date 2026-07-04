import AppKit

enum FileVisualCategory: Equatable {
    case folder
    case symbolicLink
    case package
    case hidden
    case executable
    case archive
    case image
    case audio
    case video
    case document
    case sourceCode
    case data
    case diskImage
    case fallback
}

enum FileVisualModifier: Hashable {
    case hidden
    case executable
    case symbolicLink
    case package
}

struct FileVisualStyle: Equatable {
    let category: FileVisualCategory
    let modifiers: Set<FileVisualModifier>
}

enum FileTypeClassifier {
    private static let executableMask = 0o111
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "xz", "zip"
    ]
    private static let imageExtensions: Set<String> = [
        "gif", "heic", "jpeg", "jpg", "png", "tiff", "webp"
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav", "wma"
    ]
    private static let videoExtensions: Set<String> = [
        "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"
    ]
    private static let documentExtensions: Set<String> = [
        "doc", "docx", "key", "md", "numbers", "pages", "pdf", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"
    ]
    private static let sourceCodeExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js", "jsx", "kt", "m", "mm", "php", "py", "rb", "rs", "scss", "sh", "swift", "ts", "tsx", "zsh"
    ]
    private static let dataExtensions: Set<String> = [
        "csv", "db", "json", "plist", "sqlite", "toml", "tsv", "xml", "yaml", "yml"
    ]
    private static let dataFilenames: Set<String> = [
        ".env"
    ]
    private static let diskImageExtensions: Set<String> = [
        "dmg", "img", "iso", "pkg"
    ]

    static func category(for item: FileItem) -> FileVisualCategory {
        style(for: item).category
    }

    static func style(for item: FileItem) -> FileVisualStyle {
        var modifiers = Set<FileVisualModifier>()
        if item.isHidden {
            modifiers.insert(.hidden)
        }
        if isExecutable(item) {
            modifiers.insert(.executable)
        }
        if item.isSymbolicLink || item.fileType == .symbolicLink {
            modifiers.insert(.symbolicLink)
        }
        if item.fileType == .package {
            modifiers.insert(.package)
        }

        return FileVisualStyle(category: primaryCategory(for: item), modifiers: modifiers)
    }

    private static func primaryCategory(for item: FileItem) -> FileVisualCategory {
        if item.isDirectory || item.fileType == .folder {
            return .folder
        }

        if item.isSymbolicLink || item.fileType == .symbolicLink {
            return .symbolicLink
        }

        if item.fileType == .package {
            return .package
        }

        let normalizedFilename = item.filename.lowercased()
        if dataFilenames.contains(normalizedFilename) {
            return .data
        }

        let fileExtension = item.fileExtension.lowercased()
        if archiveExtensions.contains(fileExtension) {
            return .archive
        }

        if imageExtensions.contains(fileExtension) {
            return .image
        }

        if audioExtensions.contains(fileExtension) {
            return .audio
        }

        if videoExtensions.contains(fileExtension) {
            return .video
        }

        if documentExtensions.contains(fileExtension) {
            return .document
        }

        if sourceCodeExtensions.contains(fileExtension) {
            return .sourceCode
        }

        if dataExtensions.contains(fileExtension) {
            return .data
        }

        if diskImageExtensions.contains(fileExtension) {
            return .diskImage
        }

        if isExecutable(item) {
            return .executable
        }

        if item.isHidden {
            return .hidden
        }

        return .fallback
    }

    private static func isExecutable(_ item: FileItem) -> Bool {
        guard let permissions = item.posixPermissions else { return false }
        return permissions & executableMask != 0
    }
}

enum FileTypeColorPalette {
    static let folder = NSColor.systemCyan
    static let symbolicLink = NSColor.systemPurple
    static let package = NSColor.systemGreen
    static let hidden = NSColor.secondaryLabelColor
    static let executable = NSColor.systemGreen
    static let archive = NSColor.systemOrange
    static let image = NSColor.systemTeal
    static let audio = NSColor.systemPink
    static let video = NSColor.systemIndigo
    static let document = LiquidGlassStyle.label
    static let sourceCode = LiquidGlassStyle.label
    static let data = LiquidGlassStyle.label
    static let diskImage = NSColor.systemBrown
    static let fallback = LiquidGlassStyle.label
    private static let hiddenAlpha: CGFloat = 0.62

    static func color(for style: FileVisualStyle, appearance: NSAppearance?) -> NSColor {
        let categoryColor = color(for: style.category, appearance: appearance)
        guard style.modifiers.contains(.hidden) else { return categoryColor }
        return categoryColor.withAlphaComponent(hiddenAlpha)
    }

    static func color(for category: FileVisualCategory, appearance: NSAppearance?) -> NSColor {
        let resolvedColor: NSColor
        switch category {
        case .folder:
            resolvedColor = folder
        case .symbolicLink:
            resolvedColor = symbolicLink
        case .package:
            resolvedColor = package
        case .hidden:
            resolvedColor = hidden
        case .executable:
            resolvedColor = executable
        case .archive:
            resolvedColor = archive
        case .image:
            resolvedColor = image
        case .audio:
            resolvedColor = audio
        case .video:
            resolvedColor = video
        case .document:
            resolvedColor = document
        case .sourceCode:
            resolvedColor = sourceCode
        case .data:
            resolvedColor = data
        case .diskImage:
            resolvedColor = diskImage
        case .fallback:
            resolvedColor = fallback
        }

        guard let appearance else { return resolvedColor }
        return resolvedColor.resolvedColor(with: appearance)
    }
}

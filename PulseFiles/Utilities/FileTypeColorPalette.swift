import AppKit

enum FileVisualCategory: Hashable {
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

struct FileColorScheme {
    let colors: [FileVisualCategory: NSColor]

    init(colors: [FileVisualCategory: NSColor]) {
        self.colors = colors
    }

    func color(for category: FileVisualCategory) -> NSColor {
        colors[category] ?? Self.default.colors[category] ?? LiquidGlassStyle.label
    }
}

extension FileColorScheme {
    static let `default` = FileColorScheme(colors: [
        .folder: NSColor.systemCyan,
        .symbolicLink: NSColor.systemPurple,
        .package: NSColor.systemGreen,
        .hidden: NSColor.secondaryLabelColor,
        .executable: NSColor.systemGreen,
        .archive: NSColor.systemOrange,
        .image: NSColor.systemTeal,
        .audio: NSColor.systemPink,
        .video: NSColor.systemIndigo,
        .document: LiquidGlassStyle.label,
        .sourceCode: LiquidGlassStyle.label,
        .data: LiquidGlassStyle.label,
        .diskImage: NSColor.systemBrown,
        .fallback: LiquidGlassStyle.label
    ])

    static let minimal = FileColorScheme(colors: [
        .folder: LiquidGlassStyle.label,
        .symbolicLink: LiquidGlassStyle.label,
        .package: LiquidGlassStyle.label,
        .hidden: NSColor.secondaryLabelColor,
        .executable: LiquidGlassStyle.label,
        .archive: LiquidGlassStyle.label,
        .image: LiquidGlassStyle.label,
        .audio: LiquidGlassStyle.label,
        .video: LiquidGlassStyle.label,
        .document: LiquidGlassStyle.label,
        .sourceCode: LiquidGlassStyle.label,
        .data: LiquidGlassStyle.label,
        .diskImage: LiquidGlassStyle.label,
        .fallback: LiquidGlassStyle.label
    ])

    static let highContrast = FileColorScheme(colors: [
        .folder: NSColor.systemBlue,
        .symbolicLink: NSColor.systemPurple,
        .package: NSColor.systemGreen,
        .hidden: NSColor.tertiaryLabelColor,
        .executable: NSColor.systemGreen,
        .archive: NSColor.systemOrange,
        .image: NSColor.systemTeal,
        .audio: NSColor.systemPink,
        .video: NSColor.systemIndigo,
        .document: NSColor.labelColor,
        .sourceCode: NSColor.systemYellow,
        .data: NSColor.systemMint,
        .diskImage: NSColor.systemRed,
        .fallback: NSColor.labelColor
    ])

    static let classicCommander = FileColorScheme(colors: [
        .folder: NSColor.systemBlue,
        .symbolicLink: NSColor.systemCyan,
        .package: NSColor.systemGreen,
        .hidden: NSColor.secondaryLabelColor,
        .executable: NSColor.systemGreen,
        .archive: NSColor.systemRed,
        .image: NSColor.systemPink,
        .audio: NSColor.systemPurple,
        .video: NSColor.systemOrange,
        .document: NSColor.labelColor,
        .sourceCode: NSColor.systemYellow,
        .data: NSColor.systemMint,
        .diskImage: NSColor.systemBrown,
        .fallback: NSColor.labelColor
    ])
}

enum FileTypeColorPalette {
    static let folder = FileColorScheme.default.color(for: .folder)
    static let symbolicLink = FileColorScheme.default.color(for: .symbolicLink)
    static let package = FileColorScheme.default.color(for: .package)
    static let hidden = FileColorScheme.default.color(for: .hidden)
    static let executable = FileColorScheme.default.color(for: .executable)
    static let archive = FileColorScheme.default.color(for: .archive)
    static let image = FileColorScheme.default.color(for: .image)
    static let audio = FileColorScheme.default.color(for: .audio)
    static let video = FileColorScheme.default.color(for: .video)
    static let document = FileColorScheme.default.color(for: .document)
    static let sourceCode = FileColorScheme.default.color(for: .sourceCode)
    static let data = FileColorScheme.default.color(for: .data)
    static let diskImage = FileColorScheme.default.color(for: .diskImage)
    static let fallback = FileColorScheme.default.color(for: .fallback)

    static var activeScheme = FileColorScheme.default

    private static let hiddenAlpha: CGFloat = 0.62

    static func textColor(for item: FileItem, isSelected: Bool, isActivePane: Bool, appearance: NSAppearance?) -> NSColor {
        textColor(
            for: FileTypeClassifier.style(for: item),
            isSelected: isSelected,
            isActivePane: isActivePane,
            appearance: appearance
        )
    }

    static func textColor(for style: FileVisualStyle, isSelected: Bool, isActivePane: Bool, appearance: NSAppearance?) -> NSColor {
        let categoryColor = color(for: style, appearance: appearance)
        guard isSelected else { return categoryColor }

        let selectedTextColor = (isActivePane ? NSColor.selectedTextColor : NSColor.unemphasizedSelectedTextColor)
            .resolvedColorIfNeeded(with: appearance)
        return blend(categoryColor, over: selectedTextColor, fraction: 0.28)
    }

    static func color(for style: FileVisualStyle, appearance: NSAppearance?) -> NSColor {
        let categoryColor = color(for: style.category, appearance: appearance)
        guard style.modifiers.contains(.hidden) else { return categoryColor }
        return categoryColor.withAlphaComponent(hiddenAlpha)
    }

    static func color(for category: FileVisualCategory, appearance: NSAppearance?) -> NSColor {
        activeScheme.color(for: category).resolvedColorIfNeeded(with: appearance)
    }

    private static func blend(_ categoryColor: NSColor, over selectedTextColor: NSColor, fraction: CGFloat) -> NSColor {
        let clampedFraction = max(0, min(1, fraction))
        guard let foreground = categoryColor.usingColorSpace(.deviceRGB),
              let background = selectedTextColor.usingColorSpace(.deviceRGB) else {
            return selectedTextColor
        }

        return NSColor(
            deviceRed: (foreground.redComponent * clampedFraction) + (background.redComponent * (1 - clampedFraction)),
            green: (foreground.greenComponent * clampedFraction) + (background.greenComponent * (1 - clampedFraction)),
            blue: (foreground.blueComponent * clampedFraction) + (background.blueComponent * (1 - clampedFraction)),
            alpha: max(foreground.alphaComponent, background.alphaComponent)
        )
    }
}


private extension NSColor {
    func resolvedColorIfNeeded(with appearance: NSAppearance?) -> NSColor {
        guard let appearance else { return self }

        var resolvedColor = self
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = self.usingColorSpace(.deviceRGB) ?? self
        }
        return resolvedColor
    }
}

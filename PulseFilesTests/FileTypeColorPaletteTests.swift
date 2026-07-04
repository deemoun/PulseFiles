import AppKit
import XCTest
@testable import PulseFiles

final class FileTypeClassifierTests: XCTestCase {
    func testFolderUsesFolderCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("Documents", type: .folder, isDirectory: true)), .folder)
    }

    func testSymbolicLinkUsesSymbolicLinkCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("current", type: .symbolicLink, isSymbolicLink: true)), .symbolicLink)
    }

    func testPackageUsesPackageCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("Example.app", type: .package)), .package)
    }

    func testHiddenFileKeepsPrimaryCategoryWithHiddenModifier() {
        let style = FileTypeClassifier.style(for: item(".env", isHidden: true))

        XCTAssertEqual(style.category, .data)
        XCTAssertEqual(style.modifiers, [.hidden])
    }

    func testHiddenArchiveKeepsArchiveCategoryWithHiddenModifier() {
        let style = FileTypeClassifier.style(for: item(".backup.zip", isHidden: true))

        XCTAssertEqual(style.category, .archive)
        XCTAssertEqual(style.modifiers, [.hidden])
    }

    func testHiddenSourceAndConfigFilesKeepPrimaryCategoryWithHiddenModifier() {
        let sourceStyle = FileTypeClassifier.style(for: item(".hooks.swift", isHidden: true))
        let configStyle = FileTypeClassifier.style(for: item(".config.json", isHidden: true))

        XCTAssertEqual(sourceStyle.category, .sourceCode)
        XCTAssertEqual(sourceStyle.modifiers, [.hidden])
        XCTAssertEqual(configStyle.category, .data)
        XCTAssertEqual(configStyle.modifiers, [.hidden])
    }

    func testHiddenFolderKeepsFolderCategoryWithHiddenModifier() {
        let style = FileTypeClassifier.style(for: item(".cache", type: .folder, isDirectory: true, isHidden: true))

        XCTAssertEqual(style.category, .folder)
        XCTAssertEqual(style.modifiers, [.hidden])
    }

    func testHiddenExecutableUsesExecutableCategoryAndHiddenModifier() {
        let style = FileTypeClassifier.style(for: item(".build-tool", isHidden: true, permissions: 0o100))

        XCTAssertEqual(style.category, .executable)
        XCTAssertEqual(style.modifiers, [.hidden, .executable])
    }

    func testExecutableFileUsesExecutableCategoryWhenAnyExecuteBitIsSet() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("script", permissions: 0o100)), .executable)
        XCTAssertEqual(FileTypeClassifier.category(for: item("script", permissions: 0o010)), .executable)
        XCTAssertEqual(FileTypeClassifier.category(for: item("script", permissions: 0o001)), .executable)
    }

    func testArchiveExtensionsUseArchiveCategory() {
        for filename in ["archive.zip", "backup.tar", "logs.gz", "bundle.bz2", "rootfs.xz", "volume.7z", "set.rar"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .archive, filename)
        }
    }

    func testImageExtensionsUseImageCategory() {
        for filename in ["image.png", "photo.jpg", "photo.jpeg", "animation.gif", "asset.webp", "capture.heic", "scan.tiff"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .image, filename)
        }
    }

    func testAudioExtensionsUseAudioCategory() {
        for filename in ["song.mp3", "voice.m4a", "sample.aac", "recording.wav", "mix.flac", "podcast.ogg", "render.aiff"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .audio, filename)
        }
    }

    func testVideoExtensionsUseVideoCategory() {
        for filename in ["clip.mp4", "trailer.mov", "export.m4v", "movie.mkv", "capture.avi", "stream.webm"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .video, filename)
        }
    }

    func testDocumentExtensionsUseDocumentCategory() {
        for filename in ["report.pdf", "draft.doc", "proposal.docx", "notes.rtf", "design.pages", "budget.xls", "forecast.xlsx", "slides.ppt", "deck.pptx", "talk.key", "ledger.numbers"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .document, filename)
        }
    }

    func testSourceCodeExtensionsUseSourceCodeCategory() {
        for filename in ["App.swift", "main.c", "vector.cpp", "header.h", "template.hpp", "View.m", "Bridge.mm", "lib.rs", "server.go", "script.py", "task.rb", "Controller.java", "Screen.kt", "index.js", "types.ts", "Component.tsx", "Widget.jsx", "page.html", "style.css", "theme.scss", "install.sh", "profile.zsh"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .sourceCode, filename)
        }
    }

    func testDataExtensionsUseDataCategory() {
        for filename in ["config.json", "compose.yaml", "metadata.yml", "settings.toml", "Info.plist", "layout.xml", "export.csv", "store.sqlite", "cache.db"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .data, filename)
        }
    }

    func testDiskImageExtensionsUseDiskImageCategory() {
        for filename in ["installer.dmg", "archive.iso", "backup.img", "distribution.pkg"] {
            XCTAssertEqual(FileTypeClassifier.category(for: item(filename)), .diskImage, filename)
        }
    }

    func testUnknownExtensionUsesFallbackCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("unknown.custom")), .fallback)
    }
}

final class FileTypeColorPaletteTests: XCTestCase {

    func testHiddenStyleAppliesReducedAlphaToPrimaryCategoryColor() {
        let style = FileVisualStyle(category: .archive, modifiers: [.hidden])
        let color = FileTypeColorPalette.color(for: style, appearance: nil)

        XCTAssertEqual(color.alphaComponent, 0.62, accuracy: 0.001)
    }

    func testColorMappingForEachCategory() {
        XCTAssertSameColor(FileTypeColorPalette.color(for: .folder, appearance: nil), FileTypeColorPalette.folder)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .symbolicLink, appearance: nil), FileTypeColorPalette.symbolicLink)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .package, appearance: nil), FileTypeColorPalette.package)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .hidden, appearance: nil), FileTypeColorPalette.hidden)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .executable, appearance: nil), FileTypeColorPalette.executable)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .archive, appearance: nil), FileTypeColorPalette.archive)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .image, appearance: nil), FileTypeColorPalette.image)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .audio, appearance: nil), FileTypeColorPalette.audio)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .video, appearance: nil), FileTypeColorPalette.video)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .document, appearance: nil), FileTypeColorPalette.document)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .sourceCode, appearance: nil), FileTypeColorPalette.sourceCode)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .data, appearance: nil), FileTypeColorPalette.data)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .diskImage, appearance: nil), FileTypeColorPalette.diskImage)
        XCTAssertSameColor(FileTypeColorPalette.color(for: .fallback, appearance: nil), FileTypeColorPalette.fallback)
    }
}

private func item(
    _ name: String,
    type: FileItemType = .file,
    isDirectory: Bool = false,
    isSymbolicLink: Bool = false,
    isHidden: Bool = false,
    permissions: Int? = nil
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        filename: name,
        displayName: name,
        fileExtension: URL(fileURLWithPath: name).pathExtension,
        fileType: type,
        isDirectory: isDirectory,
        isSymbolicLink: isSymbolicLink,
        isHidden: isHidden,
        size: 0,
        creationDate: nil,
        modificationDate: nil,
        posixPermissions: permissions,
        owner: nil,
        group: nil,
        localizedTypeDescription: "File",
        icon: NSImage()
    )
}

private func XCTAssertSameColor(_ actual: NSColor, _ expected: NSColor, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(actual.isEqual(expected), message(), file: file, line: line)
}

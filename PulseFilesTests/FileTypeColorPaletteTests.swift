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

    func testHiddenFileUsesHiddenCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item(".env", isHidden: true)), .hidden)
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

    func testMediaDocumentSourceDataAndDiskImageExtensionsUseSemanticCategories() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("song.mp3")), .audio)
        XCTAssertEqual(FileTypeClassifier.category(for: item("movie.mp4")), .video)
        XCTAssertEqual(FileTypeClassifier.category(for: item("README.md")), .document)
        XCTAssertEqual(FileTypeClassifier.category(for: item("main.swift")), .sourceCode)
        XCTAssertEqual(FileTypeClassifier.category(for: item("config.json")), .data)
        XCTAssertEqual(FileTypeClassifier.category(for: item("installer.dmg")), .diskImage)
    }

    func testUnknownExtensionUsesFallbackCategory() {
        XCTAssertEqual(FileTypeClassifier.category(for: item("unknown.custom")), .fallback)
    }
}

final class FileTypeColorPaletteTests: XCTestCase {
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

import AppKit
import XCTest
@testable import PulseFiles

final class FileTypeColorPaletteTests: XCTestCase {
    func testFolderUsesFolderColor() {
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("Documents", type: .folder, isDirectory: true)), FileTypeColorPalette.folder)
    }

    func testSymbolicLinkUsesSymbolicLinkColor() {
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("current", type: .symbolicLink, isSymbolicLink: true)), FileTypeColorPalette.symbolicLink)
    }

    func testPackageUsesPackageColor() {
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("Example.app", type: .package)), FileTypeColorPalette.package)
    }

    func testHiddenFileUsesHiddenColor() {
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item(".env", isHidden: true)), FileTypeColorPalette.hidden)
    }

    func testExecutableFileUsesExecutableColorWhenAnyExecuteBitIsSet() {
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("script", permissions: 0o100)), FileTypeColorPalette.executable)
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("script", permissions: 0o010)), FileTypeColorPalette.executable)
        XCTAssertSameColor(FileTypeColorPalette.textColor(for: item("script", permissions: 0o001)), FileTypeColorPalette.executable)
    }

    func testArchiveExtensionsUseArchiveColor() {
        for filename in ["archive.zip", "backup.tar", "logs.gz", "bundle.bz2", "rootfs.xz", "volume.7z", "set.rar"] {
            XCTAssertSameColor(FileTypeColorPalette.textColor(for: item(filename)), FileTypeColorPalette.archive, filename)
        }
    }

    func testImageExtensionsUseImageColor() {
        for filename in ["image.png", "photo.jpg", "photo.jpeg", "animation.gif", "asset.webp", "capture.heic", "scan.tiff"] {
            XCTAssertSameColor(FileTypeColorPalette.textColor(for: item(filename)), FileTypeColorPalette.image, filename)
        }
    }

    func testTextAndSourceExtensionsUseTextColor() {
        for filename in ["main.swift", "notes.txt", "README.md", "config.json", "settings.yaml", "layout.xml", "index.html", "styles.css", "app.js", "types.ts"] {
            XCTAssertSameColor(FileTypeColorPalette.textColor(for: item(filename)), FileTypeColorPalette.text, filename)
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
}

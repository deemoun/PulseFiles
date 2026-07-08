import AppKit
import XCTest
@testable import PulseFiles

final class FileSortingTests: XCTestCase {
    func testFoldersSortBeforeFiles() {
        let file = item("a.txt", isDirectory: false, size: 1)
        let folder = item("z-folder", isDirectory: true, size: 0)

        let sorted = FileSystemService.sorted([file, folder], descriptor: .init(key: .name, ascending: true))

        XCTAssertEqual(sorted.map(\.displayName), ["z-folder", "a.txt"])
    }

    func testDirectorySizeDisplayUsesPlaceholder() {
        let folder = item("folder", isDirectory: true, size: 0)

        XCTAssertEqual(FilePaneViewController.sizeDisplayString(for: folder), "--")
    }

    func testSizeSortingUsesNameAsTieBreaker() {
        let b = item("b.txt", isDirectory: false, size: 10)
        let a = item("a.txt", isDirectory: false, size: 10)

        let sorted = FileSystemService.sorted([b, a], descriptor: .init(key: .size, ascending: true))

        XCTAssertEqual(sorted.map(\.displayName), ["a.txt", "b.txt"])
    }

    func testKindSortingUsesTypeDescriptionThenName() {
        let image = item("z-image.png", isDirectory: false, size: 10, typeDescription: "PNG image")
        let textB = item("b.txt", isDirectory: false, size: 10, typeDescription: "Text document")
        let textA = item("a.txt", isDirectory: false, size: 10, typeDescription: "Text document")

        let sorted = FileSystemService.sorted([textB, image, textA], descriptor: .init(key: .kind, ascending: true))

        XCTAssertEqual(sorted.map(\.displayName), ["z-image.png", "a.txt", "b.txt"])
    }

    func testDirectorySizeSortingUsesPlaceholderSizeAndNameTieBreaker() {
        let beta = item("beta", isDirectory: true, size: 0)
        let alpha = item("alpha", isDirectory: true, size: 0)

        let sorted = FileSystemService.sorted([beta, alpha], descriptor: .init(key: .size, ascending: true))

        XCTAssertEqual(sorted.map(\.displayName), ["alpha", "beta"])
    }

    private func item(_ name: String, isDirectory: Bool, size: Int64, typeDescription: String? = nil) -> FileItem {
        let resolvedTypeDescription = typeDescription ?? (isDirectory ? "Folder" : "File")
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            filename: name,
            displayName: name,
            fileExtension: URL(fileURLWithPath: name).pathExtension,
            fileType: isDirectory ? .folder : .file,
            isDirectory: isDirectory,
            isSymbolicLink: false,
            isHidden: name.hasPrefix("."),
            size: size,
            creationDate: nil,
            modificationDate: nil,
            posixPermissions: nil,
            owner: nil,
            group: nil,
            typeDescription: resolvedTypeDescription,
            localizedTypeDescription: resolvedTypeDescription,
            icon: NSImage()
        )
    }
}

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

    func testDescendingSortsKeepFoldersBeforeFiles() {
        let oldFolder = item(
            "a-old-folder",
            isDirectory: true,
            size: 1,
            typeDescription: "Folder",
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let newFolder = item(
            "z-new-folder",
            isDirectory: true,
            size: 50,
            typeDescription: "Folder",
            modificationDate: Date(timeIntervalSince1970: 300)
        )
        let oldFile = item(
            "a-old-file.txt",
            isDirectory: false,
            size: 10,
            typeDescription: "Text document",
            modificationDate: Date(timeIntervalSince1970: 200)
        )
        let newFile = item(
            "z-new-file.png",
            isDirectory: false,
            size: 100,
            typeDescription: "PNG image",
            modificationDate: Date(timeIntervalSince1970: 400)
        )
        let items = [oldFile, oldFolder, newFile, newFolder]

        let cases: [(FileSortKey, [String])] = [
            (.name, ["z-new-folder", "a-old-folder", "z-new-file.png", "a-old-file.txt"]),
            (.size, ["z-new-folder", "a-old-folder", "z-new-file.png", "a-old-file.txt"]),
            (.kind, ["z-new-folder", "a-old-folder", "a-old-file.txt", "z-new-file.png"]),
            (.modified, ["z-new-folder", "a-old-folder", "z-new-file.png", "a-old-file.txt"])
        ]

        for (key, expectedNames) in cases {
            let sorted = FileSystemService.sorted(items, descriptor: .init(key: key, ascending: false))

            XCTAssertEqual(sorted.map(\.displayName), expectedNames, "Failed descending sort for \(key)")
            XCTAssertTrue(sorted.prefix(2).allSatisfy(\.isDirectory), "Directories should stay first for \(key)")
            XCTAssertFalse(sorted.suffix(2).contains(where: \.isDirectory), "Files should stay after directories for \(key)")
        }
    }

    private func item(
        _ name: String,
        isDirectory: Bool,
        size: Int64,
        typeDescription: String? = nil,
        modificationDate: Date? = nil
    ) -> FileItem {
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
            modificationDate: modificationDate,
            posixPermissions: nil,
            owner: nil,
            group: nil,
            typeDescription: resolvedTypeDescription,
            localizedTypeDescription: resolvedTypeDescription,
            icon: NSImage()
        )
    }
}

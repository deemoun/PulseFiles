import AppKit
import Foundation
@testable import PulseFiles

final class TestFileSystem: FileSystemServicing {
    private var itemsByDirectory: [URL: [FileItem]]
    private(set) var requests: [(url: URL, includingHidden: Bool, sort: FileSortDescriptor)] = []

    init(itemsByDirectory: [URL: [FileItem]] = [:]) {
        self.itemsByDirectory = itemsByDirectory
    }

    func setItems(_ items: [FileItem], for directory: URL) {
        itemsByDirectory[directory] = items
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> [FileItem] {
        requests.append((url: url, includingHidden: includingHidden, sort: sort))
        let items = itemsByDirectory[url, default: []]
        let visibleItems = includingHidden ? items : items.filter { !$0.isHidden }
        return FileSystemService.sorted(visibleItems, descriptor: sort)
    }

    static func item(
        named name: String,
        in directory: URL,
        isDirectory: Bool = false,
        size: Int64 = 0,
        modified: Date? = nil
    ) -> FileItem {
        let url = directory.appendingPathComponent(name, isDirectory: isDirectory)
        return FileItem(
            url: url,
            filename: name,
            displayName: name,
            fileExtension: url.pathExtension,
            fileType: isDirectory ? .folder : .file,
            isDirectory: isDirectory,
            isSymbolicLink: false,
            isHidden: name.hasPrefix("."),
            size: size,
            creationDate: nil,
            modificationDate: modified,
            posixPermissions: nil,
            owner: nil,
            group: nil,
            localizedTypeDescription: isDirectory ? "Folder" : "File",
            icon: NSImage()
        )
    }
}

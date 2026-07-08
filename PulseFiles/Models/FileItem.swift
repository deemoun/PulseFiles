import AppKit
import Foundation

struct FileItem: Identifiable, Equatable {
    let url: URL
    let filename: String
    let displayName: String
    let fileExtension: String
    let fileType: FileItemType
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
    let posixPermissions: Int?
    let owner: String?
    let group: String?
    let typeDescription: String
    let localizedTypeDescription: String
    let icon: NSImage

    var id: URL { url }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

enum FileItemType: String {
    case folder
    case symbolicLink
    case package
    case file
    case unknown
}

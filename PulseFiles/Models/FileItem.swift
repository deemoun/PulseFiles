import Foundation

/// Metadata that determines a reusable Finder-style icon without retaining an
/// AppKit image in every directory item.
struct FileIconKey: Hashable {
    let fileType: FileItemType
    let fileExtension: String
    let contentTypeIdentifier: String?
    let isAlias: Bool

    init(fileType: FileItemType, fileExtension: String, contentTypeIdentifier: String? = nil, isAlias: Bool = false) {
        self.fileType = fileType
        self.fileExtension = fileExtension.lowercased()
        self.contentTypeIdentifier = contentTypeIdentifier?.lowercased()
        self.isAlias = isAlias
    }
}

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
    let addedDate: Date?
    let accessDate: Date?
    let posixPermissions: Int?
    let owner: String?
    let group: String?
    let typeDescription: String
    let localizedTypeDescription: String
    let iconKey: FileIconKey

    var id: URL { url }

    init(url: URL, filename: String, displayName: String, fileExtension: String, fileType: FileItemType, isDirectory: Bool, isSymbolicLink: Bool, isHidden: Bool, size: Int64, creationDate: Date?, modificationDate: Date?, addedDate: Date? = nil, accessDate: Date? = nil, posixPermissions: Int?, owner: String?, group: String?, typeDescription: String, localizedTypeDescription: String, iconKey: FileIconKey) {
        self.url = url; self.filename = filename; self.displayName = displayName
        self.fileExtension = fileExtension; self.fileType = fileType; self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink; self.isHidden = isHidden; self.size = size
        self.creationDate = creationDate; self.modificationDate = modificationDate
        self.addedDate = addedDate; self.accessDate = accessDate
        self.posixPermissions = posixPermissions; self.owner = owner; self.group = group
        self.typeDescription = typeDescription; self.localizedTypeDescription = localizedTypeDescription; self.iconKey = iconKey
    }

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

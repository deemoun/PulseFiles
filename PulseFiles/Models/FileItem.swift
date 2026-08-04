import Foundation
import PulseFilesUtilities

/// Metadata that determines a reusable Finder-style icon without retaining an
/// AppKit image in every directory item.
package struct FileIconKey: Hashable {
    package let fileType: FileItemType
    package let fileExtension: String
    package let contentTypeIdentifier: String?
    package let isAlias: Bool

    package init(fileType: FileItemType, fileExtension: String, contentTypeIdentifier: String? = nil, isAlias: Bool = false) {
        self.fileType = fileType
        self.fileExtension = fileExtension.lowercased()
        self.contentTypeIdentifier = contentTypeIdentifier?.lowercased()
        self.isAlias = isAlias
    }
}

package struct FileItem: Identifiable, Equatable {
    package let url: URL
    package let filename: String
    package let displayName: String
    package let fileExtension: String
    package let fileType: FileItemType
    package let isDirectory: Bool
    package let isSymbolicLink: Bool
    package let isHidden: Bool
    package let size: Int64
    package let creationDate: Date?
    package let modificationDate: Date?
    package let addedDate: Date?
    package let accessDate: Date?
    package let posixPermissions: Int?
    package let owner: String?
    package let group: String?
    package let typeDescription: String
    package let localizedTypeDescription: String
    package let iconKey: FileIconKey

    package var id: URL { url }

    package init(url: URL, filename: String, displayName: String, fileExtension: String, fileType: FileItemType, isDirectory: Bool, isSymbolicLink: Bool, isHidden: Bool, size: Int64, creationDate: Date?, modificationDate: Date?, addedDate: Date? = nil, accessDate: Date? = nil, posixPermissions: Int?, owner: String?, group: String?, typeDescription: String, localizedTypeDescription: String, iconKey: FileIconKey) {
        self.url = url; self.filename = filename; self.displayName = displayName
        self.fileExtension = fileExtension; self.fileType = fileType; self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink; self.isHidden = isHidden; self.size = size
        self.creationDate = creationDate; self.modificationDate = modificationDate
        self.addedDate = addedDate; self.accessDate = accessDate
        self.posixPermissions = posixPermissions; self.owner = owner; self.group = group
        self.typeDescription = typeDescription; self.localizedTypeDescription = localizedTypeDescription; self.iconKey = iconKey
    }

    package static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

package enum FileItemType: String {
    case folder
    case symbolicLink
    case package
    case file
    case unknown
}

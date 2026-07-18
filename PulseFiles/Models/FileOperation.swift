import Foundation

enum FileOperationKind {
    case createFolder
    case createFile
    case copy
    case move
    case trash
    case delete
    case rename
}

struct FileOperation {
    let kind: FileOperationKind
    let sources: [URL]
    let destination: URL?
}


/// Complete before/after state retained only for operations that can be reversed safely.
struct FileOperationRecovery: Equatable {
    enum Kind: Equatable { case rename, move }
    struct Item: Equatable {
        let originalURL: URL
        let destinationURL: URL
    }
    let kind: Kind
    let items: [Item]
}

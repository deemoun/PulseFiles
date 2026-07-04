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

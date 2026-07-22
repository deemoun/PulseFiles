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
    /// A recovery is issued only when its original operation completed without
    /// replacement, cancellation, cleanup warnings, or provider uncertainty.
    enum Kind: Equatable { case rename, move, copy, trash }
    struct Item: Equatable {
        let originalURL: URL
        let destinationURL: URL
        /// The platform resource identity captured immediately after creating
        /// a copy (or after placing an item in Trash). A missing identity makes
        /// destructive copy recovery unavailable rather than guessing.
        let destinationIdentity: String?

        init(originalURL: URL, destinationURL: URL, destinationIdentity: String? = nil) {
            self.originalURL = originalURL
            self.destinationURL = destinationURL
            self.destinationIdentity = destinationIdentity
        }
    }
    let kind: Kind
    let items: [Item]

    var undoTitle: String {
        switch kind {
        case .copy: return "Undo Copy"
        case .move: return "Undo Move"
        case .rename: return "Undo Rename"
        case .trash: return "Undo Move to Trash"
        }
    }
}

import Foundation

enum FileOperationKind {
    case createFolder
    case createFile
    case copy
    case move
    case trash
    case delete
    case rename
    case createArchive
    case extractArchive
    case batchRename
}

/// A deliberately narrow archive format. PulseFiles writes ZIP files itself;
/// it never interpolates paths into a shell command.
enum ArchiveFormat: Equatable { case zip }

struct ArchiveSafetyLimits: Equatable {
    var maximumItemCount: Int
    var maximumExpandedBytes: Int64
    var maximumPathDepth: Int

    static let `default` = ArchiveSafetyLimits(maximumItemCount: 100_000, maximumExpandedBytes: 10 * 1_024 * 1_024 * 1_024, maximumPathDepth: 100)
}

struct ArchiveCreateRequest: Equatable {
    let sources: [URL]
    let destinationURL: URL
    let format: ArchiveFormat
    let limits: ArchiveSafetyLimits

    init(sources: [URL], destinationURL: URL, format: ArchiveFormat = .zip, limits: ArchiveSafetyLimits = .default) {
        self.sources = sources; self.destinationURL = destinationURL; self.format = format; self.limits = limits
    }
}

struct ArchiveExtractRequest: Equatable {
    let archiveURL: URL
    let destinationDirectory: URL
    let limits: ArchiveSafetyLimits

    init(archiveURL: URL, destinationDirectory: URL, limits: ArchiveSafetyLimits = .default) {
        self.archiveURL = archiveURL; self.destinationDirectory = destinationDirectory; self.limits = limits
    }
}

struct BatchRenameItem: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

/// Immutable preview. Execution accepts only this complete preflight product,
/// so the UI cannot rename an unpreviewed path.
struct BatchRenamePlan: Equatable {
    let items: [BatchRenameItem]
}

struct BatchRenameRequest: Equatable {
    let sources: [URL]
    /// Produces the proposed name for the source and its zero-based index.
    let proposedNames: [String]

    init(sources: [URL], proposedNames: [String]) {
        self.sources = sources; self.proposedNames = proposedNames
    }
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

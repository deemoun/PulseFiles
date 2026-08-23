import Foundation
import PulseFilesUtilities

package enum FileOperationKind {
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
package enum ArchiveFormat: Equatable { case zip }

package struct ArchiveSafetyLimits: Equatable {
    package var maximumItemCount: Int
    package var maximumExpandedBytes: Int64
    package var maximumPathDepth: Int

    package static let `default` = ArchiveSafetyLimits(maximumItemCount: 100_000, maximumExpandedBytes: 10 * 1_024 * 1_024 * 1_024, maximumPathDepth: 100)
}

package struct ArchiveCreateRequest: Equatable {
    package let sources: [URL]
    package let destinationURL: URL
    package let format: ArchiveFormat
    package let limits: ArchiveSafetyLimits

    package init(sources: [URL], destinationURL: URL, format: ArchiveFormat = .zip, limits: ArchiveSafetyLimits = .default) {
        self.sources = sources; self.destinationURL = destinationURL; self.format = format; self.limits = limits
    }
}

package struct ArchiveExtractRequest: Equatable {
    package let archiveURL: URL
    package let destinationDirectory: URL
    package let limits: ArchiveSafetyLimits

    package init(archiveURL: URL, destinationDirectory: URL, limits: ArchiveSafetyLimits = .default) {
        self.archiveURL = archiveURL; self.destinationDirectory = destinationDirectory; self.limits = limits
    }
}

package struct BatchRenameItem: Equatable {
    package let sourceURL: URL
    package let destinationURL: URL

    package init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

/// Immutable preview. Execution accepts only this complete preflight product,
/// so the UI cannot rename an unpreviewed path.
package struct BatchRenamePlan: Equatable {
    package let items: [BatchRenameItem]

    package init(items: [BatchRenameItem]) {
        self.items = items
    }
}

package struct BatchRenameRequest: Equatable {
    package let sources: [URL]
    /// Produces the proposed name for the source and its zero-based index.
    package let proposedNames: [String]

    package init(sources: [URL], proposedNames: [String]) {
        self.sources = sources; self.proposedNames = proposedNames
    }
}

package struct FileOperation {
    package let kind: FileOperationKind
    package let sources: [URL]
    package let destination: URL?
}


/// Complete before/after state retained only for operations that can be reversed safely.
package struct FileOperationRecovery: Equatable {
    /// V1 is intentionally an allow-list. Creation, permanent deletion,
    /// archives, extraction, and batch rename are visibly unsupported.
    package enum Version: Equatable { case v1 }
    /// A recovery is issued only when its original operation completed without
    /// replacement, cancellation, cleanup warnings, or provider uncertainty.
    package enum Kind: Equatable { case rename, move, copy, trash }
    package enum Eligibility: Equatable {
        case eligible
        case expired
        case unsupportedOperation
        case incompleteOperation
    }
    package struct Item: Equatable {
        package let originalURL: URL
        package let destinationURL: URL
        /// The platform resource identity captured immediately after creating
        /// a copy (or after placing an item in Trash). A missing identity makes
        /// destructive copy recovery unavailable rather than guessing.
        package let destinationIdentity: String?

        package init(originalURL: URL, destinationURL: URL, destinationIdentity: String? = nil) {
            self.originalURL = originalURL
            self.destinationURL = destinationURL
            self.destinationIdentity = destinationIdentity
        }
    }
    package let kind: Kind
    package let items: [Item]
    package let version: Version
    package let issuedAt: Date
    package let expiresAt: Date

    package init(kind: Kind, items: [Item], issuedAt: Date = Date(), lifetime: TimeInterval = 10 * 60) {
        self.kind = kind; self.items = items; self.version = .v1; self.issuedAt = issuedAt
        self.expiresAt = issuedAt.addingTimeInterval(max(0, lifetime))
    }

    package func eligibility(at date: Date = Date()) -> Eligibility {
        guard !items.isEmpty else { return .incompleteOperation }
        return date < expiresAt ? .eligible : .expired
    }

    package static func supportsV1(_ operation: FileOperationKind) -> Bool {
        switch operation {
        case .copy, .move, .trash, .rename: return true
        case .createFolder, .createFile, .delete, .createArchive, .extractArchive, .batchRename: return false
        }
    }

    package var undoTitle: String {
        switch kind {
        case .copy: return "Undo Copy"
        case .move: return "Undo Move"
        case .rename: return "Undo Rename"
        case .trash: return "Undo Move to Trash"
        }
    }
}

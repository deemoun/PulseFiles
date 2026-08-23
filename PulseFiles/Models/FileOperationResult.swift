import Foundation
import PulseFilesUtilities

package enum FileOperationError: LocalizedError, Equatable {
    case emptySelection
    case duplicateSource(URL)
    /// Multi-source operations reject overlapping paths instead of attempting
    /// an order-dependent partial mutation of a parent and its descendant.
    case overlappingSources(ancestor: URL, descendant: URL)
    case duplicateDestination(URL)
    case sourceMissing(URL)
    case destinationDirectoryMissing(URL)
    case destinationNotDirectory(URL)
    case destinationInsideSource(source: URL, destination: URL)
    case destinationExists(URL)
    case unsafeReplacement(destination: URL, backup: URL)
    case sourceCleanupFailed(source: URL, destination: URL)
    case temporarySiblingUnavailable(destination: URL, prefix: String)
    case insufficientDestinationCapacity(required: Int64, available: Int64)
    case iCloudItemNotDownloaded(URL)
    case finderAliasMutationUnsupported(URL)
    case readOnlyVolume(URL)
    case volumeUnavailable(URL)
    case traversalLimitExceeded(URL, maximumDepth: Int, maximumItems: Int)
    case undoUnavailable

    package var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No files are selected.".localized
        case .duplicateSource(let url):
            return "%@ is selected more than once.".localized(with: url.lastPathComponent)
        case .overlappingSources(let ancestor, let descendant):
            return "%@ and %@ cannot be selected together.".localized(with: ancestor.lastPathComponent, descendant.lastPathComponent)
        case .duplicateDestination(let url):
            return "Multiple selected items would write to %@.".localized(with: url.lastPathComponent)
        case .sourceMissing(let url):
            return "%@ no longer exists.".localized(with: url.lastPathComponent)
        case .destinationDirectoryMissing:
            return "The destination folder does not exist.".localized
        case .destinationNotDirectory(let url):
            return "%@ is not a folder.".localized(with: url.lastPathComponent)
        case .destinationInsideSource:
            return "Cannot copy or move a folder into itself.".localized
        case .destinationExists(let url):
            return "%@ already exists.".localized(with: url.lastPathComponent)
        case .unsafeReplacement:
            return "Could not safely replace the existing item.".localized
        case .sourceCleanupFailed:
            return "The item was copied, but the original could not be removed.".localized
        case .temporarySiblingUnavailable:
            return "Could not create a safe temporary file name.".localized
        case .insufficientDestinationCapacity:
            return "The destination does not have enough available space.".localized
        case .iCloudItemNotDownloaded(let url):
            return "%@ is stored in iCloud and has not finished downloading.".localized(with: url.lastPathComponent)
        case .finderAliasMutationUnsupported(let url):
            return "%@ is a Finder alias and cannot be changed in PulseFiles.".localized(with: url.lastPathComponent)
        case .readOnlyVolume(let url):
            return "%@ is on a read-only volume.".localized(with: url.lastPathComponent)
        case .volumeUnavailable(let url):
            return "The volume containing %@ is no longer available.".localized(with: url.lastPathComponent)
        case .traversalLimitExceeded(let url, _, _):
            return "%@ is too deeply nested or contains too many items to transfer safely.".localized(with: url.lastPathComponent)
        case .undoUnavailable:
            return "This operation can no longer be safely undone.".localized
        }
    }

    private static func formattedByteCount(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    package var failureReason: String? {
        switch self {
        case .emptySelection:
            return "Select one or more items in the active pane.".localized
        case .duplicateSource(let url):
            return "PulseFiles rejected the operation before changing files because %@ appeared more than once.".localized(with: url.path)
        case .overlappingSources(let ancestor, let descendant):
            return "PulseFiles rejected the operation before changing files because %@ contains %@.".localized(with: ancestor.path, descendant.path)
        case .duplicateDestination(let url):
            return "PulseFiles rejected the operation before changing files because more than one source would write to %@.".localized(with: url.path)
        case .sourceMissing(let url):
            return "%@ was not found before the operation started.".localized(with: url.path)
        case .destinationDirectoryMissing(let url):
            return "%@ was not found before the operation started.".localized(with: url.path)
        case .destinationNotDirectory(let url):
            return "%@ must be a folder.".localized(with: url.path)
        case .destinationInsideSource(let source, let destination):
            return "Cannot copy or move %@ into %@.".localized(with: source.lastPathComponent, destination.path)
        case .destinationExists(let url):
            return "The destination already contains %@.".localized(with: url.lastPathComponent)
        case .unsafeReplacement(let destination, let backup):
            return "The original item was kept at %@. %@ was not overwritten.".localized(with: backup.path, destination.path)
        case .sourceCleanupFailed(let source, let destination):
            return "%@ now exists, but the original remains at %@.".localized(with: destination.path, source.path)
        case .temporarySiblingUnavailable(let destination, let prefix):
            return "PulseFiles tried multiple %@ staging names beside %@, but each candidate already existed.".localized(with: prefix, destination.path)
        case .insufficientDestinationCapacity(let required, let available):
            return "This operation requires %@, but the destination volume has only %@ available.".localized(with: Self.formattedByteCount(required), Self.formattedByteCount(available))
        case .iCloudItemNotDownloaded(let url):
            return "Download %@ in Finder, then try again. PulseFiles did not change any files.".localized(with: url.path)
        case .finderAliasMutationUnsupported(let url):
            return "Use Finder to manage %@, or select its original item. PulseFiles did not change the alias or its target.".localized(with: url.path)
        case .readOnlyVolume(let url):
            return "Choose a writable destination or eject the read-only media before modifying %@.".localized(with: url.path)
        case .volumeUnavailable(let url):
            return "Reconnect or remount the volume containing %@, then try again.".localized(with: url.path)
        case .traversalLimitExceeded(let url, let maximumDepth, let maximumItems):
            return "PulseFiles stopped before exhausting process resources while traversing %@. The safety limits are a depth of %@ and %@ items.".localized(with: url.path, String(maximumDepth), String(maximumItems))
        case .undoUnavailable:
            return "The operation was partial, cancelled, or did not retain a complete safe reversal path.".localized
        }
    }
}

/// Snapshot used to reject states that cannot safely be mutated.  It is
/// injectable so tests can cover removable, network, and iCloud conditions
/// without depending on the machine running the tests.
package struct FileOperationPathSafetyState: Equatable {
    package var isAvailable = true
    package var isReadOnlyVolume = false
    package var isICloudPlaceholder = false
    /// Finder aliases are not symbolic links. Mutations reject the alias
    /// object before resolving or changing it or its target.
    package var isFinderAlias = false
}

package enum FileConflictResolution: Equatable {
    case replace
    case skip
    case keepBoth
    case cancel
    case applyToRemainingReplace
    case applyToRemainingSkip
    case applyToRemainingKeepBoth
}

package enum FileTransferCapacityPreflight: Equatable {
    case notRequired
    case sufficient(required: Int64, available: Int64)
    case insufficient(required: Int64, available: Int64)
    case cannotVerify(required: Int64?)
}

package struct FileOperationRequest {
    package let sources: [URL]
    package let destinationDirectory: URL
}

package struct FileOperationProgress {
    package let currentItemName: String
    package let completedCount: Int
    package let totalCount: Int
    package let completedRecursiveItemCount: Int?
    package let totalRecursiveItemCount: Int?
    package let completedByteCount: Int64?
    package let totalByteCount: Int64?
    package let isPreparingTransfer: Bool

    package init(
        currentItemName: String,
        completedCount: Int,
        totalCount: Int,
        completedRecursiveItemCount: Int? = nil,
        totalRecursiveItemCount: Int? = nil,
        completedByteCount: Int64? = nil,
        totalByteCount: Int64? = nil,
        isPreparingTransfer: Bool = false
    ) {
        self.currentItemName = currentItemName
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.completedRecursiveItemCount = completedRecursiveItemCount
        self.totalRecursiveItemCount = totalRecursiveItemCount
        self.completedByteCount = completedByteCount
        self.totalByteCount = totalByteCount
        self.isPreparingTransfer = isPreparingTransfer
    }
}

package struct FileOperationItemFailure {
    package let url: URL
    package let error: Error

    package init(url: URL, error: Error) {
        self.url = url
        self.error = error
    }
}

package struct FileOperationCleanupWarning {
    package let url: URL
    package let message: String

    package init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

package struct FileOperationResult {
    package let completedItems: [URL]
    package let skippedItems: [URL]
    package let failedItems: [FileOperationItemFailure]
    package let cleanupWarnings: [FileOperationCleanupWarning]
    package let wasCancelled: Bool
    /// `true` means the caller stopped waiting while a filesystem call could
    /// still be running. The resulting paths must be verified before reuse.
    package let needsVerification: Bool
    package let recovery: FileOperationRecovery?

    package init(
        completedItems: [URL],
        skippedItems: [URL],
        failedItems: [FileOperationItemFailure],
        cleanupWarnings: [FileOperationCleanupWarning] = [],
        wasCancelled: Bool,
        needsVerification: Bool = false,
        recovery: FileOperationRecovery? = nil
    ) {
        self.completedItems = completedItems
        self.skippedItems = skippedItems
        self.failedItems = failedItems
        self.cleanupWarnings = cleanupWarnings
        self.wasCancelled = wasCancelled
        self.needsVerification = needsVerification
        self.recovery = recovery
    }

    package var succeededCompletely: Bool {
        !wasCancelled && !needsVerification && skippedItems.isEmpty && failedItems.isEmpty && cleanupWarnings.isEmpty
    }

    package static func unknownAfterAbandoning(currentItem: URL? = nil) -> Self {
        Self(
            completedItems: [],
            skippedItems: [],
            failedItems: [],
            wasCancelled: false,
            needsVerification: true
        )
    }
}

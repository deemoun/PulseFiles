// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesCapabilities
import PulseFilesModels

/// Contract-level doubles keep presentation tests independent of production
/// filesystem services, schedulers, bookmarks, and mutation engines.
final class FileSystemCapabilityDouble: FileSystemServicing {
    var contentsResult = DirectoryContentsResult(items: [], itemReadFailures: [])
    var snapshotResult = DirectorySnapshotMetadata(resourceIdentifier: nil, changeDate: nil)
    var requestedDirectories: [URL] = []

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        requestedDirectories.append(url)
        return contentsResult
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata { snapshotResult }
}

final class AccessPolicyCapabilityDouble: BrowseAccessPolicy, AccessPolicyStatusProviding {
    var rootURL = URL(fileURLWithPath: "/")
    var isEnabled = false
    var isAllowed = true

    func canAccess(_ url: URL, logDecision shouldLogDecision: Bool) -> Bool { isAllowed }
    func validateAccess(to url: URL) throws {
        if !isAllowed { throw CocoaError(.fileReadNoPermission) }
    }
    func validatedDirectory(_ url: URL, fallback: URL?) -> URL { isAllowed ? url : (fallback ?? rootURL) }
    func withValidatedAccess<T>(to url: URL, _ body: () async throws -> T) async throws -> T {
        try validateAccess(to: url)
        return try await body()
    }
}

final class StagingCleanupCapabilityDouble: StagingCleanupProviding, @unchecked Sendable {
    var inventoryResult = StagingCleanupInventory(candidates: [], legacyItemsForReview: [])
    var cleanupResult = StagingCleanupResult(removed: [], failures: [])
    func inventory(olderThan cutoff: Date?, includeLegacyReview: Bool) throws -> StagingCleanupInventory { inventoryResult }
    func cleanup(_ candidates: [StagingCleanupCandidate]) async -> StagingCleanupResult { cleanupResult }
}

final class ScratchCleanupCapabilityDouble: ScratchFolderCleanupProviding, @unchecked Sendable {
    var selection: ScratchFolderSelection
    var inventoryResult: ScratchFolderInventory
    var cleanupResult = FileOperationResult(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: false)

    init(directory: URL) {
        selection = ScratchFolderSelection(directory: directory, identity: "test", resolvedPath: directory.path)
        inventoryResult = ScratchFolderInventory(selection: selection, deletionURLs: [], itemCount: 0, allocatedByteCount: 0)
    }
    func captureSelection(for directory: URL) throws -> ScratchFolderSelection { selection }
    func inventory(for selection: ScratchFolderSelection) throws -> ScratchFolderInventory { inventoryResult }
    func cleanup(_ inventory: ScratchFolderInventory, action: ScratchFolderCleanupAction?) async throws -> FileOperationResult { cleanupResult }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum ScratchFolderCleanupAction: Equatable, Sendable {
    case moveToTrash
    case permanentlyDelete
}

package struct ScratchFolderSelection: Equatable, Sendable {
    package let directory: URL
    package let identity: String
    package let resolvedPath: String

    package init(directory: URL, identity: String, resolvedPath: String) {
        self.directory = directory
        self.identity = identity
        self.resolvedPath = resolvedPath
    }
}

package struct ScratchFolderInventory: Sendable {
    package let selection: ScratchFolderSelection
    package let deletionURLs: [URL]
    package let itemCount: Int
    package let allocatedByteCount: Int64
}

package enum ScratchFolderCleanupError: LocalizedError, Equatable {
    case notDirectory(URL)
    case inaccessible(URL)
    case unsafeLocation(URL)
    case symbolicLink(URL)
    case uncertainTarget(URL)

    package var errorDescription: String? {
        switch self {
        case .notDirectory: return "The scratch folder is missing or is not a directory.".localized
        case .inaccessible: return "The scratch folder could not be read.".localized
        case .unsafeLocation: return "That location is too broad to use for scratch-folder cleanup.".localized
        case .symbolicLink: return "A scratch folder reached through a symbolic link cannot be cleaned safely.".localized
        case .uncertainTarget: return "The scratch folder has moved, been replaced, or changed since it was selected.".localized
        }
    }

    package var failureReason: String? {
        switch self {
        case .notDirectory(let url), .inaccessible(let url), .unsafeLocation(let url),
             .symbolicLink(let url), .uncertainTarget(let url):
            return "No contents were changed. Choose the folder again after verifying this path: %@".localized(with: url.path)
        }
    }
}

/// Explicitly inventories and cleans a user-owned scratch folder. This is
/// intentionally unrelated to PulseFiles' privately owned transfer staging.
package final class ScratchFolderCleanupService: @unchecked Sendable {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy
    private let fileOperations: FileOperationServicing
    private let activePaneRoots: () -> [URL]
    private let identity: (URL) -> String?

    package init(
        fileManager: FileManager = .default,
        accessPolicy: SandboxFileAccessPolicy = .current,
        fileOperations: FileOperationServicing? = nil,
        activePaneRoots: @escaping () -> [URL] = { [] },
        identity: @escaping (URL) -> String? = StagingCleanupService.resourceIdentity
    ) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.fileOperations = fileOperations ?? FileOperationService(fileManager: fileManager, accessPolicy: accessPolicy)
        self.activePaneRoots = activePaneRoots
        self.identity = identity
    }

    package func captureSelection(for directory: URL) throws -> ScratchFolderSelection {
        try validateDirectory(directory, expectedSelection: nil)
        guard let identity = identity(directory) else { throw ScratchFolderCleanupError.uncertainTarget(directory) }
        return .init(directory: directory.standardizedFileURL, identity: identity, resolvedPath: directory.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    package func inventory(for selection: ScratchFolderSelection) throws -> ScratchFolderInventory {
        try validateDirectory(selection.directory, expectedSelection: selection)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let deletionURLs: [URL]
        do {
            deletionURLs = try fileManager.contentsOfDirectory(at: selection.directory, includingPropertiesForKeys: keys, options: [])
        } catch {
            throw ScratchFolderCleanupError.inaccessible(selection.directory)
        }

        var itemCount = 0
        var allocatedByteCount: Int64 = 0
        for child in deletionURLs {
            try validateDeletionDestination(child, inside: selection.directory)
            itemCount += 1
            allocatedByteCount += allocatedSize(of: child, itemCount: &itemCount)
        }
        return .init(selection: selection, deletionURLs: deletionURLs, itemCount: itemCount, allocatedByteCount: allocatedByteCount)
    }

    package func cleanup(_ inventory: ScratchFolderInventory, action: ScratchFolderCleanupAction?) async throws -> FileOperationResult {
        guard let action else {
            return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true)
        }
        try validateDirectory(inventory.selection.directory, expectedSelection: inventory.selection)
        for url in inventory.deletionURLs {
            try validateDeletionDestination(url, inside: inventory.selection.directory)
            guard fileManager.fileExists(atPath: url.path) else { throw ScratchFolderCleanupError.uncertainTarget(url) }
        }
        guard !inventory.deletionURLs.isEmpty else {
            return .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: false)
        }
        switch action {
        case .moveToTrash:
            return try await fileOperations.trash(inventory.deletionURLs, progressHandler: nil)
        case .permanentlyDelete:
            return try await fileOperations.delete(inventory.deletionURLs, progressHandler: nil)
        }
    }

    private func validateDirectory(_ directory: URL, expectedSelection: ScratchFolderSelection?) throws {
        let url = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw expectedSelection == nil ? ScratchFolderCleanupError.notDirectory(url) : ScratchFolderCleanupError.uncertainTarget(url)
        }
        try accessPolicy.validateAccess(to: url)
        try accessPolicy.validateDestinationAccess(to: url.appendingPathComponent(".pulsefiles-cleanup-validation"))
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == url.path else { throw ScratchFolderCleanupError.symbolicLink(url) }

        let protectedPaths = ["/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/bin", "/etc", "/private", "/sbin", "/tmp", "/usr", "/var"]
        let volumeRoots = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil)?.map(\.standardizedFileURL) ?? []
        let protected = protectedPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [fileManager.homeDirectoryForCurrentUser]
            + volumeRoots
            + activePaneRoots()
        guard !protected.contains(where: { $0.standardizedFileURL.path == url.path }),
              url.pathComponents.count > 2 else {
            throw ScratchFolderCleanupError.unsafeLocation(url)
        }
        if let expectedSelection,
           (expectedSelection.resolvedPath != resolved.path || expectedSelection.identity != identity(url)) {
            throw ScratchFolderCleanupError.uncertainTarget(url)
        }
    }

    private func validateDeletionDestination(_ url: URL, inside directory: URL) throws {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path == directory.standardizedFileURL.path else { throw ScratchFolderCleanupError.uncertainTarget(url) }
        try accessPolicy.validateAccess(to: url)
        try accessPolicy.validateDestinationAccess(to: url)
    }

    private func allocatedSize(of url: URL, itemCount: inout Int) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let rootValues = try? url.resourceValues(forKeys: keys)
        var total = Int64(rootValues?.totalFileAllocatedSize ?? rootValues?.fileAllocatedSize ?? 0)
        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true,
              let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) else { return total }
        for case let child as URL in enumerator {
            itemCount += 1
            let values = try? child.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            if values?.isSymbolicLink == true { enumerator.skipDescendants() }
        }
        return total
    }
}

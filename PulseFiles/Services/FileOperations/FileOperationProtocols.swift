// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package protocol FileOperationCloudDownloadPreparing: Sendable {
    func prepareDownload(for url: URL) async throws -> Bool
}

package protocol FileOperationServicing {
    func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func createFolder(named rawName: String, in directory: URL) async throws -> FileOperationResult
    func createFile(named rawName: String, in directory: URL) async throws -> FileOperationResult
    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
}

/// Optional archive capability kept separate so small filesystem clients and
/// their test doubles cannot accidentally inherit a silent no-op.
package protocol FileOperationArchiveServicing {
    func createArchive(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
    func extractArchive(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult
}

/// Optional batch-rename capability. Conformers must implement every entry
/// point; there are deliberately no fallback implementations.
package protocol FileOperationBatchRenameServicing {
    func planBatchRename(_ request: BatchRenameRequest) throws -> BatchRenamePlan
    func batchRename(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler?) async -> FileOperationResult
}

package typealias FileOperationCoordinating = FileOperationServicing & FileOperationArchiveServicing & FileOperationBatchRenameServicing

package protocol FileOperationFileManaging {
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at URL: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws
    func createEmptyFile(at url: URL) throws
    func destinationOfSymbolicLink(atPath path: String) throws -> String
    func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws
    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
}

/// The byte-oriented part of a transfer is deliberately separate from the
/// filesystem coordinator so it can be exercised without relying on
/// `FileManager.copyItem`'s opaque progress behaviour.
package protocol FileOperationStreamingCopying {
    func copyFile(
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int) async throws -> Void
    ) async throws
}

#if os(macOS)
package extension FileOperationStreamingCopying {
    /// The production copier overrides this path so creation is relative to a
    /// checked directory descriptor.  The URL fallback keeps test copiers
    /// source-compatible; it is never used by `FileHandleStreamingCopier`.
    func copyFile(from source: URL, toParent parent: OpenDirectoryCapability, named name: String, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        try parent.revalidate()
        try OpenDirectoryCapability.validateName(name)
        try await copyFile(from: source, to: parent.directoryURL.appendingPathComponent(name), progress: progress)
    }
}
#endif

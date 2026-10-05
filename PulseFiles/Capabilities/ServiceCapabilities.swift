// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels

// MARK: - Browsing and probing

package struct DirectoryItemReadFailure {
    package let url: URL
    package let error: Error
    package init(url: URL, error: Error) { self.url = url; self.error = error }
}

package struct DirectoryContentsReadError: LocalizedError {
    package let failures: [DirectoryItemReadFailure]
    package init(failures: [DirectoryItemReadFailure]) { self.failures = failures }
    package var errorDescription: String? { "Could not read metadata for \(failures.count) item(s)." }
}

package struct DirectoryLoadTimeoutError: LocalizedError, Equatable {
    package let timeout: TimeInterval
    package init(timeout: TimeInterval) { self.timeout = timeout }
    package var errorDescription: String? { "Folder is taking too long to respond. Try again." }
}

package struct DirectorySnapshotMetadata: Equatable, Sendable {
    package let resourceIdentifier: String?
    package let changeDate: Date?
    package init(resourceIdentifier: String?, changeDate: Date?) { self.resourceIdentifier = resourceIdentifier; self.changeDate = changeDate }
}

package struct DirectoryContentsResult {
    package let items: [FileItem]
    package let itemReadFailures: [DirectoryItemReadFailure]
    package init(items: [FileItem], itemReadFailures: [DirectoryItemReadFailure]) { self.items = items; self.itemReadFailures = itemReadFailures }
    package var isComplete: Bool { itemReadFailures.isEmpty }
}

package protocol FileSystemServicing: AnyObject {
    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult
    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata
}

package enum FileSystemProbeAnswer<Value: Sendable>: Sendable, Equatable where Value: Equatable {
    case value(Value), timedOut, unavailable
}

package protocol FileSystemProbing: Sendable {
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?>
    func isApplicationBundle(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool>
}
package extension FileSystemProbing {
    func isApplicationBundle(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { .unavailable }
}

// MARK: - Access and grants

package struct FolderAccessGrant: Codable, Equatable {
    package let url: URL
    package let bookmarkData: Data
    package init(url: URL, bookmarkData: Data) { self.url = url; self.bookmarkData = bookmarkData }
}

package struct FolderAccessScope {
    package let urls: [URL]
    package init(urls: [URL]) { self.urls = urls }
    package var isActive: Bool { !urls.isEmpty }
}

package enum FolderAccessGrantStatus: Equatable { case noMatchingGrant, staleOrUnavailable, available, inaccessible }
package protocol FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data
    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool)
}
package protocol FolderAccessGrantProviding: AnyObject {
    var grants: [FolderAccessGrant] { get set }
    func grantAccess(to directory: URL) throws -> FolderAccessGrant
    func refreshResolvedGrants()
    @discardableResult func removeGrant(for directory: URL) -> Bool
}
package extension FolderAccessGrantProviding {
    var grants: [FolderAccessGrant] { get { [] } set {} }
    func refreshResolvedGrants() {}
    @discardableResult func removeGrant(for directory: URL) -> Bool { false }
}

package protocol FileAccessValidating: AnyObject {
    func canAccess(_ url: URL, logDecision shouldLogDecision: Bool) -> Bool
    func validateAccess(to url: URL) throws
}
package extension FileAccessValidating { func canAccess(_ url: URL) -> Bool { canAccess(url, logDecision: true) } }
package protocol BrowseAccessPolicy: FileAccessValidating {
    var rootURL: URL { get }; var isEnabled: Bool { get }
    func validatedDirectory(_ url: URL, fallback: URL?) -> URL
    func withValidatedAccess<T>(to url: URL, _ body: () async throws -> T) async throws -> T
}
package extension BrowseAccessPolicy { func validatedDirectory(_ url: URL) -> URL { validatedDirectory(url, fallback: nil) } }
package protocol OperationScopeAccessPolicy: FileAccessValidating {
    func beginAccess(to urls: [URL]) -> FolderAccessScope
    func endAccess(_ scope: FolderAccessScope)
}
package protocol AccessPolicyStatusProviding: AnyObject { var rootURL: URL { get }; var isEnabled: Bool { get } }

package enum StandardFolder: String, CaseIterable {
    case desktop
    case documents
    case downloads
}

package enum StandardFolderAccessState: Equatable {
    case accessible
    case deniedOrUnavailable
    case requiresSystemSettingsReview
    case blockedByExperimentalSandbox
}

// MARK: - Cleanup

package enum ScratchFolderCleanupAction: Equatable, Sendable { case moveToTrash, permanentlyDelete }
package struct ScratchFolderSelection: Equatable, Sendable {
    package let directory: URL; package let identity: String; package let resolvedPath: String
    package init(directory: URL, identity: String, resolvedPath: String) { self.directory = directory; self.identity = identity; self.resolvedPath = resolvedPath }
}
package struct ScratchFolderInventory: Sendable {
    package let selection: ScratchFolderSelection; package let deletionURLs: [URL]; package let itemCount: Int; package let allocatedByteCount: Int64
    package init(selection: ScratchFolderSelection, deletionURLs: [URL], itemCount: Int, allocatedByteCount: Int64) { self.selection = selection; self.deletionURLs = deletionURLs; self.itemCount = itemCount; self.allocatedByteCount = allocatedByteCount }
}
package protocol ScratchFolderCleanupProviding: Sendable {
    func captureSelection(for directory: URL) throws -> ScratchFolderSelection
    func inventory(for selection: ScratchFolderSelection) throws -> ScratchFolderInventory
    func cleanup(_ inventory: ScratchFolderInventory, action: ScratchFolderCleanupAction?) async throws -> FileOperationResult
}

package enum StagingOperationState: String, Codable, Sendable { case active, completed }
package struct StagingOwnershipRecord: Codable, Equatable, Sendable {
    package let operationID: UUID; package let stagingURL: URL; package let createdAt: Date; package let destinationURL: URL
    package let stagingIdentity: String; package let destinationIdentity: String; package var state: StagingOperationState
    package init(operationID: UUID, stagingURL: URL, createdAt: Date, destinationURL: URL, stagingIdentity: String, destinationIdentity: String, state: StagingOperationState) {
        self.operationID = operationID; self.stagingURL = stagingURL; self.createdAt = createdAt; self.destinationURL = destinationURL
        self.stagingIdentity = stagingIdentity; self.destinationIdentity = destinationIdentity; self.state = state
    }
}
package struct StagingCleanupCandidate: Equatable, Sendable {
    package let record: StagingOwnershipRecord; package let byteCount: Int64
    package init(record: StagingOwnershipRecord, byteCount: Int64) { self.record = record; self.byteCount = byteCount }
}
package struct StagingCleanupInventory: Equatable, Sendable {
    package let candidates: [StagingCleanupCandidate]; package let legacyItemsForReview: [URL]
    package init(candidates: [StagingCleanupCandidate], legacyItemsForReview: [URL]) { self.candidates = candidates; self.legacyItemsForReview = legacyItemsForReview }
    package var totalByteCount: Int64 { candidates.reduce(0) { $0 + $1.byteCount } }
}
package struct StagingCleanupFailure: Sendable { package let url: URL; package let message: String; package init(url: URL, message: String) { self.url = url; self.message = message } }
package struct StagingCleanupResult: Sendable { package let removed: [URL]; package let failures: [StagingCleanupFailure]; package init(removed: [URL], failures: [StagingCleanupFailure]) { self.removed = removed; self.failures = failures } }
package protocol StagingCleanupProviding: Sendable {
    func inventory(olderThan cutoff: Date?, includeLegacyReview: Bool) throws -> StagingCleanupInventory
    func cleanup(_ candidates: [StagingCleanupCandidate]) async -> StagingCleanupResult
}
package extension StagingCleanupProviding { func inventory() throws -> StagingCleanupInventory { try inventory(olderThan: nil, includeLegacyReview: true) } }

// MARK: - Persistence and navigation

package protocol SettingsPersisting: AnyObject {
    var snapshot: SettingsSnapshot { get }
    func update(_ mutation: (inout SettingsSnapshot) -> Void)
    func importJSONIfChanged()
    @discardableResult func writeSettingsJSON() throws -> URL
}
package enum StartupDirectorySource: Equatable { case `default`, lastVisited, userSelected }
package struct StartupDirectoryResolution {
    package let directory: URL; package let requestedDirectory: URL; package let source: StartupDirectorySource; package let needsAccessRecovery: Bool
    package init(directory: URL, requestedDirectory: URL, source: StartupDirectorySource, needsAccessRecovery: Bool) { self.directory = directory; self.requestedDirectory = requestedDirectory; self.source = source; self.needsAccessRecovery = needsAccessRecovery }
}
package protocol StartupDirectoryResolving: AnyObject {
    func resolution(for pane: PaneID) -> StartupDirectoryResolution
    func validatedSavedDirectory(path: String?, fallback: URL) -> URL
}

// MARK: - Sidebar storage and sizing

package struct DirectorySizeResult: Sendable, Equatable {
    package enum Completeness: Sendable, Equatable { case complete, partial(skippedItemCount: Int) }
    package let bytes: Int64; package let completeness: Completeness
    package init(bytes: Int64, completeness: Completeness) { self.bytes = bytes; self.completeness = completeness }
}
package protocol DirectorySizing: Sendable { func size(of root: URL) async throws -> DirectorySizeResult }
package protocol RecentLocationRecording: AnyObject { var locations: [URL] { get }; var onChange: (([URL]) -> Void)? { get set }; func record(_ url: URL) }
package protocol BookmarkPersisting: AnyObject { func load() -> [Bookmark]; func save(_ bookmarks: [Bookmark]) }

// MARK: - Diagnostics export

package struct DiagnosticsExportRequest: Sendable, Equatable {
    package let destinationDirectory: URL
    package let renderedContents: String
    package init(destinationDirectory: URL, renderedContents: String) { self.destinationDirectory = destinationDirectory; self.renderedContents = renderedContents }
}
package struct DiagnosticsExportResult: Sendable, Equatable { package let bundleURL: URL; package init(bundleURL: URL) { self.bundleURL = bundleURL } }
package protocol DiagnosticsExportCapability: Sendable { func export(_ request: DiagnosticsExportRequest) throws -> DiagnosticsExportResult }

// MARK: - Terminal process

/// Narrow process capability used by the opt-in terminal presentation. The
/// service implementation keeps writable descriptor construction behind the
/// services boundary.
package protocol TerminalProcess: AnyObject {
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    var outputHandler: ((Data) -> Void)? { get set }
    var terminationHandler: ((TerminalProcess) -> Void)? { get set }
    func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL)
    func run() throws
    func write(_ data: Data)
    func resize(columns: Int, rows: Int)
    func terminate()
}

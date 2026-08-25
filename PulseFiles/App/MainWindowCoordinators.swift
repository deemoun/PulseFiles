import AppKit
import Foundation

// MARK: - Injectable application boundaries

protocol DescendantSearching {
    func search(query: DescendantSearchQuery, limits: DescendantSearchLimits, onBatch: DescendantSearchBatchHandler?) async throws -> DescendantSearchResult
}

extension DescendantSearching {
    func search(query: DescendantSearchQuery) async throws -> DescendantSearchResult {
        try await search(query: query, limits: .init(), onBatch: nil)
    }
}

protocol RecentLocationRecording: AnyObject {
    var locations: [URL] { get }
    var onChange: (([URL]) -> Void)? { get set }
    func record(_ url: URL)
}

protocol BookmarkPersisting: AnyObject {
    func load() -> [Bookmark]
    func save(_ bookmarks: [Bookmark])
}

protocol FileClipboardProviding: AnyObject {
    var changeCount: Int { get }
    func write(urls: [URL], operation: FileClipboard.Operation)
    func read() -> FileClipboard.Payload?
}

protocol FileSizeResolving { func size(of url: URL) throws -> Int64 }
protocol ViewerContentLoading: AnyObject { func snapshots(for url: URL) -> AsyncThrowingStream<ViewerSnapshot, Error> }
protocol DiagnosticsExporting { func export(to parentDirectory: URL, entries: [DiagnosticLogEntry], operationSummaries: [DiagnosticOperationSummary]) throws -> URL }
protocol TerminalStateProviding: AnyObject {
    var shellPath: String { get }
    var defaultEnvironment: [String: String] { get }
    func warningState(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy) -> TerminalWarningState
    func acknowledgeFirstUseWarning(settings: SettingsService)
    func shouldAcknowledgeFirstUseWarning(response: Int, acknowledgementResponse: Int) -> Bool
    func resolvedWorkingDirectory(activePaneURL: URL?, accessPolicy: SandboxFileAccessPolicy) -> URL
}
protocol StandardFolderAccessProviding: AnyObject { func requestAccess(for folder: StandardFolder) -> StandardFolderAccessState }
protocol ThumbnailLoading: AnyObject { func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? }

@MainActor
protocol ApplicationOpening: AnyObject {
    func open(_ url: URL) -> Bool
    func open(_ urls: [URL], withApplicationAt applicationURL: URL) -> Bool
    func reveal(_ urls: [URL])
}

extension DescendantSearchService: DescendantSearching {}
extension RecentLocationService: RecentLocationRecording {}
extension BookmarkService: BookmarkPersisting {}
extension FileClipboard: FileClipboardProviding {}
extension SystemFileSizeService: FileSizeResolving {}
extension ReadOnlyViewerService: ViewerContentLoading {}
extension DiagnosticsExportService: DiagnosticsExporting {}
extension TerminalService: TerminalStateProviding {
    func warningState(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy) -> TerminalWarningState {
        warningState(settings: settings as any TerminalSettingsProviding, accessPolicy: accessPolicy)
    }

    func acknowledgeFirstUseWarning(settings: SettingsService) {
        acknowledgeFirstUseWarning(settings: settings as any TerminalSettingsProviding)
    }
}
extension StandardFolderAccessService: StandardFolderAccessProviding {}
extension ThumbnailLoadingService: ThumbnailLoading {}

@MainActor
final class WorkspaceApplicationOpener: ApplicationOpening {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) { self.workspace = workspace }

    func open(_ url: URL) -> Bool { workspace.open(url) }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL) -> Bool {
        workspace.open(urls, withApplicationAt: applicationURL, configuration: .init()) { _, _ in }
        return true
    }

    func reveal(_ urls: [URL]) { workspace.activateFileViewerSelecting(urls) }
}

/// Dependencies are assembled above the view controller so workflow tests can
/// replace filesystem and OS integration without constructing AppKit panes.
struct MainWindowDependencies {
    let accessPolicy: SandboxFileAccessPolicy
    let paneFileSystem: any FileSystemServicing
    let folderAccessGrants: any FolderAccessGrantProviding
    let authorizedFolderSelection: AuthorizedFolderSelectionCoordinator
    let fileOperations: any FileOperationCoordinating
    let fileSystemProbe: any FileSystemProbing
    let descendantSearch: any DescendantSearching
    let recentLocations: any RecentLocationRecording
    let bookmarks: any BookmarkPersisting
    let volumeDiscovery: any VolumeDiscovering
    let directorySizing: any DirectorySizing
    let clipboard: any FileClipboardProviding
    let applicationOpener: any ApplicationOpening
    let fileSize: any FileSizeResolving
    let readOnlyViewer: any ViewerContentLoading
    let diagnosticsExporter: any DiagnosticsExporting
    let terminalState: any TerminalStateProviding
    let thumbnailLoader: any ThumbnailLoading
    let standardFolderAccess: any StandardFolderAccessProviding
    let symbolicLinkResolver: SymbolicLinkResolutionService
    let stagingCleanup: (@escaping () -> [URL]) -> StagingCleanupService
    let scratchCleanup: (@escaping () -> [URL]) -> ScratchFolderCleanupService

    @MainActor
    static func production(accessPolicy: SandboxFileAccessPolicy) -> Self {
        let scheduler = FileSystemOperationScheduler.shared
        let paneFileSystem = FileSystemService(accessPolicy: accessPolicy, scheduler: scheduler)
        let folderAccessGrants = FolderAccessGrantService.shared
        let fileOperations = FileOperationService(accessPolicy: accessPolicy)
        return Self(
            accessPolicy: accessPolicy,
            paneFileSystem: paneFileSystem,
            folderAccessGrants: folderAccessGrants,
            authorizedFolderSelection: AuthorizedFolderSelectionCoordinator(
                accessPolicy: accessPolicy,
                grantService: folderAccessGrants
            ),
            fileOperations: fileOperations,
            fileSystemProbe: FileSystemProbeService(scheduler: scheduler),
            descendantSearch: DescendantSearchService(accessPolicy: accessPolicy),
            recentLocations: RecentLocationService(),
            bookmarks: BookmarkService(),
            volumeDiscovery: VolumeDiscoveryService(),
            directorySizing: DirectorySizingService(accessPolicy: accessPolicy),
            clipboard: FileClipboard(),
            applicationOpener: WorkspaceApplicationOpener(),
            fileSize: SystemFileSizeService(),
            readOnlyViewer: ReadOnlyViewerService(accessPolicy: accessPolicy),
            diagnosticsExporter: DiagnosticsExportService(),
            terminalState: TerminalService(),
            thumbnailLoader: ThumbnailLoadingService(),
            standardFolderAccess: StandardFolderAccessService(accessPolicy: accessPolicy),
            symbolicLinkResolver: SymbolicLinkResolutionService(),
            stagingCleanup: { activeRoots in StagingCleanupService(legacyReviewDirectories: activeRoots) },
            scratchCleanup: { activeRoots in
                ScratchFolderCleanupService(accessPolicy: accessPolicy, fileOperations: fileOperations, activePaneRoots: activeRoots)
            }
        )
    }

    @MainActor
    func replacingPaneComposition(
        accessPolicy: SandboxFileAccessPolicy,
        paneFileSystem: any FileSystemServicing,
        folderAccessGrants: any FolderAccessGrantProviding,
        directorySizing: any DirectorySizing
    ) -> Self {
        Self(
            accessPolicy: accessPolicy,
            paneFileSystem: paneFileSystem,
            folderAccessGrants: folderAccessGrants,
            authorizedFolderSelection: AuthorizedFolderSelectionCoordinator(
                accessPolicy: accessPolicy,
                grantService: folderAccessGrants
            ),
            fileOperations: fileOperations,
            fileSystemProbe: fileSystemProbe,
            descendantSearch: descendantSearch,
            recentLocations: recentLocations,
            bookmarks: bookmarks,
            volumeDiscovery: volumeDiscovery,
            directorySizing: directorySizing,
            clipboard: clipboard,
            applicationOpener: applicationOpener,
            fileSize: fileSize,
            readOnlyViewer: readOnlyViewer,
            diagnosticsExporter: diagnosticsExporter,
            terminalState: terminalState,
            thumbnailLoader: thumbnailLoader,
            standardFolderAccess: standardFolderAccess,
            symbolicLinkResolver: symbolicLinkResolver,
            stagingCleanup: stagingCleanup,
            scratchCleanup: scratchCleanup
        )
    }
}

// MARK: - Workflow coordinators

struct PreviewCoordinator {
    enum Availability: Equatable { case available, blocked(String), missing }

    private let accessPolicy: SandboxFileAccessPolicy
    private let probe: any FileSystemProbing

    init(accessPolicy: SandboxFileAccessPolicy, probe: any FileSystemProbing) {
        self.accessPolicy = accessPolicy
        self.probe = probe
    }

    func availability(of url: URL) async -> Availability {
        do {
            let result = try await accessPolicy.withValidatedAccess(to: url) {
                await probe.exists(url, deadline: .milliseconds(250))
            }
            if case .value(true) = result { return .available }
            return .missing
        } catch {
            return .blocked(error.localizedDescription)
        }
    }
}

struct NavigationCoordinator {
    private let probe: any FileSystemProbing

    init(probe: any FileSystemProbing) { self.probe = probe }

    func volumeChangeActions(for directories: [URL], change: VolumeChange) async -> [VolumeChangePaneRefreshAction] {
        await VolumeChangePaneRefreshRouter.actions(for: directories, change: change) { url in
            await probe.exists(url, deadline: .milliseconds(200))
        }
    }

    func standardLocation(for command: MainCommand) -> URL {
        MainCommandDestinationResolver.destination(for: command)
    }
}

/// Value-only split state keeps window layout decisions out of command routing.
struct WindowLayoutController {
    private(set) var isSidebarVisible: Bool
    private(set) var isTerminalVisible: Bool
    private(set) var isSinglePane: Bool

    init(isSidebarVisible: Bool, isTerminalVisible: Bool, isSinglePane: Bool = false) {
        self.isSidebarVisible = isSidebarVisible
        self.isTerminalVisible = isTerminalVisible
        self.isSinglePane = isSinglePane
    }

    mutating func setSidebarVisible(_ visible: Bool) { isSidebarVisible = visible }
    mutating func setTerminalVisible(_ visible: Bool) { isTerminalVisible = visible }
    mutating func setSinglePane(_ singlePane: Bool) { isSinglePane = singlePane }
}

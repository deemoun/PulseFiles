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
    let fileOperations: any FileOperationCoordinating
    let fileSystemProbe: any FileSystemProbing
    let descendantSearch: any DescendantSearching
    let recentLocations: any RecentLocationRecording
    let bookmarks: any BookmarkPersisting
    let volumeDiscovery: any VolumeDiscovering
    let clipboard: any FileClipboardProviding
    let applicationOpener: any ApplicationOpening
    let fileSize: SystemFileSizeService
    let readOnlyViewer: ReadOnlyViewerService
    let diagnosticsExporter: DiagnosticsExportService
    let stagingCleanup: (@escaping () -> [URL]) -> StagingCleanupService
    let scratchCleanup: (@escaping () -> [URL]) -> ScratchFolderCleanupService

    @MainActor
    static func production(accessPolicy: SandboxFileAccessPolicy) -> Self {
        let scheduler = FileSystemOperationScheduler.shared
        let fileOperations = FileOperationService(accessPolicy: accessPolicy)
        return Self(
            fileOperations: fileOperations,
            fileSystemProbe: FileSystemProbeService(scheduler: scheduler),
            descendantSearch: DescendantSearchService(accessPolicy: accessPolicy),
            recentLocations: RecentLocationService(),
            bookmarks: BookmarkService(),
            volumeDiscovery: VolumeDiscoveryService(),
            clipboard: FileClipboard(),
            applicationOpener: WorkspaceApplicationOpener(),
            fileSize: SystemFileSizeService(),
            readOnlyViewer: ReadOnlyViewerService(accessPolicy: accessPolicy),
            diagnosticsExporter: DiagnosticsExportService(),
            stagingCleanup: { activeRoots in StagingCleanupService(legacyReviewDirectories: activeRoots) },
            scratchCleanup: { activeRoots in
                ScratchFolderCleanupService(accessPolicy: accessPolicy, fileOperations: fileOperations, activePaneRoots: activeRoots)
            }
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

/// Owns workflow state, result presentation, cancellation and safe undo capture.
/// AppKit supplies progress/result closures and remains responsible for pane refresh.
@MainActor
final class FileOperationCoordinator {
    private(set) var activeTask: Task<Void, Never>?
    private var retainedTasks: [Int: Task<Void, Never>] = [:]
    private(set) var generation = 0
    private(set) var currentGeneration: Int?
    private(set) var undoRecovery: FileOperationRecovery?
    private(set) var isActive = false

    func captureRecovery(from result: FileOperationResult) {
        undoRecovery = result.succeededCompletely ? result.recovery : nil
    }

    func clearRecovery() { undoRecovery = nil }
    func cancel() { activeTask?.cancel() }

    @discardableResult
    func begin() -> Int? {
        guard !isActive else { return nil }
        generation += 1
        currentGeneration = generation
        isActive = true
        return generation
    }

    func retain(_ task: Task<Void, Never>, for generation: Int) {
        guard currentGeneration == generation else { return }
        activeTask = task
        retainedTasks[generation] = task
    }

    func acceptsUpdates(for generation: Int) -> Bool { currentGeneration == generation }

    func finish(generation: Int, result: FileOperationResult?, captureRecovery: Bool) {
        retainedTasks[generation] = nil
        guard currentGeneration == generation else { return }
        if captureRecovery, let result { self.captureRecovery(from: result) }
        activeTask = nil
        currentGeneration = nil
        isActive = false
    }

    /// Releases presentation ownership while retaining the worker until it exits.
    func detach() -> Int? {
        guard let detached = currentGeneration else { return nil }
        activeTask?.cancel()
        generation += 1
        activeTask = nil
        currentGeneration = nil
        isActive = false
        undoRecovery = nil
        return detached
    }

    static func resultPresentation(_ result: FileOperationResult, operationName: String) -> (message: String, detail: String, style: NSAlert.Style)? {
        guard !result.succeededCompletely else { return nil }
        var details = [
            "Completed: %d".localized(with: result.completedItems.count),
            "Skipped: %d".localized(with: result.skippedItems.count),
            "Failed: %d".localized(with: result.failedItems.count),
            "Cleanup warnings: %d".localized(with: result.cleanupWarnings.count)
        ]
        if result.needsVerification { details.append("The operation's final filesystem state is unknown. Refresh and verify the affected items before continuing.".localized) }
        if result.wasCancelled { details.append("The whole operation was cancelled before all items completed.".localized) }
        if !result.failedItems.isEmpty { details.append("Partial failure: some selected items were not changed.".localized) }
        details.append(contentsOf: result.failedItems.map { "\($0.url.lastPathComponent): \($0.error.localizedDescription)" })
        details.append(contentsOf: result.cleanupWarnings.map { "\($0.url.lastPathComponent): \($0.message)" })
        let onlyCancelled = result.wasCancelled && !result.needsVerification && result.failedItems.isEmpty && result.cleanupWarnings.isEmpty
        let message = result.needsVerification ? "%@ Needs Verification".localized(with: operationName)
            : onlyCancelled ? "%@ Cancelled".localized(with: operationName)
            : "%@ Finished With Issues".localized(with: operationName)
        return (message, details.joined(separator: "\n"), onlyCancelled ? .informational : .warning)
    }
}

/// Owns the pasteboard session, including transient feedback and cut markers.
@MainActor
final class ClipboardSessionCoordinator {
    private let transfer: FileTransferWorkflowCoordinator
    private var feedbackTimer: Timer?
    private var changeMonitor: Timer?
    private var trackedChangeCount: Int?
    private(set) var cutURLs: Set<URL> = []

    init(transfer: FileTransferWorkflowCoordinator) { self.transfer = transfer }
    func payload() -> FileClipboard.Payload? { transfer.clipboardPayload() }
    func write(_ urls: [URL], operation: FileClipboard.Operation, onExpired: @escaping () -> Void) throws {
        try transfer.writeToClipboard(urls, operation: operation)
        cutURLs = operation == .move ? Set(urls) : []
        trackedChangeCount = transfer.clipboard.changeCount
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in onExpired() }
        changeMonitor?.invalidate()
        changeMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let trackedChangeCount, transfer.clipboard.changeCount != trackedChangeCount else { return }
            self.clear(); onExpired()
        }
    }
    func clear() {
        feedbackTimer?.invalidate(); feedbackTimer = nil
        changeMonitor?.invalidate(); changeMonitor = nil
        trackedChangeCount = nil; cutURLs = []
    }
}

/// Owns terminal policy and presentation state; split-view geometry stays in TerminalLayoutCoordinator.
@MainActor
final class TerminalPresentationCoordinator {
    enum ToggleResult: Equatable { case show, hide, disabled }
    private(set) var isVisible = false
    private let service: TerminalService
    init(service: TerminalService = TerminalService()) { self.service = service }
    func toggle(isEnabled: Bool) -> ToggleResult {
        if isVisible { isVisible = false; return .hide }
        guard isEnabled else { return .disabled }
        isVisible = true; return .show
    }
    func synchronize(installed: Bool) { isVisible = installed }
    func workingDirectory(activePaneURL: URL, accessPolicy: SandboxFileAccessPolicy) -> URL? {
        service.resolvedWorkingDirectory(activePaneURL: activePaneURL, accessPolicy: accessPolicy)
    }
    func warningState(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy) -> TerminalWarningState {
        service.warningState(settings: settings, accessPolicy: accessPolicy)
    }
    func acknowledgeWarningIfNeeded(response: Int, acknowledgementResponse: Int, settings: SettingsService) {
        guard service.shouldAcknowledgeFirstUseWarning(response: response, acknowledgementResponse: acknowledgementResponse) else { return }
        service.acknowledgeFirstUseWarning(settings: settings)
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

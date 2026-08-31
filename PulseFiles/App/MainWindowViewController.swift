// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Quartz
import UniformTypeIdentifiers

struct MainCommandDestinationResolver {
    static func destination(for command: MainCommand) -> URL {
        destination(
            for: command,
            sandboxRestricted: ExperimentalFlags.restrictFileAccessToAppSandboxRoot,
            sandboxRoot: ExperimentalFlags.appSandboxRoot,
            isDebugBuild: isDebugBuild
        )
    }

    static func destination(
        for command: MainCommand,
        sandboxRestricted: Bool,
        sandboxRoot: URL,
        isDebugBuild: Bool
    ) -> URL {
        if isDebugBuild, sandboxRestricted {
            switch command {
            case .home, .applications:
                return sandboxRoot
            case .downloads:
                return sandboxRoot.appendingPathComponent("Downloads", isDirectory: true)
            default:
                break
            }
        }

        switch command {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        case .applications:
            return FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
                ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        default:
            return sandboxRoot
        }
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

final class MainWindowViewController: NSViewController, WorkflowWindowProviding, WorkflowAlertPresenting, WorkflowOperationExecuting, WorkflowConflictResolving, ScratchDirectoryWorkflowPresenting, MainCommandHandling, FileOperationPresenting {
    private enum SidebarMetrics {
        static let minWidth: CGFloat = 220
        static let maxWidth: CGFloat = 340
        static let contentMinWidth: CGFloat = 620
    }

    private let settings: SettingsService
    private var liquidGlassStyle: LiquidGlassStyle {
        LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled)
    }
    private let accessPolicy: SandboxFileAccessPolicy
    private let authorizedFolderSelection: AuthorizedFolderSelectionCoordinator
    private let sandboxRootEnsurer: () -> Void
    private let symbolicLinkResolver: SymbolicLinkResolutionService
    private let workflows: MainWindowWorkflowDependencies
    private let fileSystem: any FileSystemServicing
    private let fileOperations: any FileOperationCoordinating
    private lazy var volumeChangeMonitor = VolumeChangeMonitor()
    private let fileSystemProbe: any FileSystemProbing
    private let recentLocations: any RecentLocationRecording
    private let bookmarkService: any BookmarkPersisting
    private let volumeDiscovery: any VolumeDiscovering
    private let directorySizing: any DirectorySizing
    private let thumbnailLoader: any ThumbnailLoading
    private let standardFolderAccess: any StandardFolderAccessProviding
    private let folderAccessGrants: any FolderAccessGrantProviding
    private var recentOperationSummaries: [DiagnosticOperationSummary] = []

    private lazy var leftStartupResolution = settings.startupDirectoryResolution(for: .left)
    private lazy var rightStartupResolution = settings.startupDirectoryResolution(for: .right)

    lazy var leftPane = FilePaneViewController(
        paneID: .left,
        viewModel: FilePaneViewModel(
            initialDirectory: leftStartupResolution.directory,
            showsHiddenFiles: settings.showHiddenFilesByDefault,
            sort: settings.sortDescriptor(for: .left),
            restoration: settings.leftPaneTabRestoration,
            fileSystem: fileSystem,
            accessPolicy: accessPolicy,
            quickSearchMatchMode: settings.quickSearchMatchMode,
            quickSearchPresentation: settings.quickSearchPresentation
        ),
        presentationMode: settings.presentationMode(for: .left),
        thumbnailLoader: thumbnailLoader,
        authorizedFolderSelection: authorizedFolderSelection,
        liquidGlassStyle: liquidGlassStyle
    )
    lazy var rightPane = FilePaneViewController(
        paneID: .right,
        viewModel: FilePaneViewModel(
            initialDirectory: rightStartupResolution.directory,
            showsHiddenFiles: settings.showHiddenFilesByDefault,
            sort: settings.sortDescriptor(for: .right),
            restoration: settings.rightPaneTabRestoration,
            fileSystem: fileSystem,
            accessPolicy: accessPolicy,
            quickSearchMatchMode: settings.quickSearchMatchMode,
            quickSearchPresentation: settings.quickSearchPresentation
        ),
        presentationMode: settings.presentationMode(for: .right),
        thumbnailLoader: thumbnailLoader,
        authorizedFolderSelection: authorizedFolderSelection,
        liquidGlassStyle: liquidGlassStyle
    )
    private lazy var sidebar = SidebarViewController(
        recentLocations: recentLocations,
        bookmarkService: bookmarkService,
        settings: settings,
        accessPolicy: accessPolicy,
        volumeDiscovery: volumeDiscovery,
        directorySizing: directorySizing,
        liquidGlassStyle: liquidGlassStyle
    )
    private let terminal: TerminalViewController
    private lazy var commandBar = CommandBarView(style: liquidGlassStyle)
    private lazy var fileOperationProgressWindowController = FileOperationProgressWindowController { [weak self] in
        self?.cancelActiveFileOperation()
    } onStopWaiting: { [weak self] in
        self?.detachActiveFileOperation()
    }
    private lazy var clipboardSession = ClipboardDropWorkflowCoordinator(
        transfer: workflows.fileTransfer,
        onCutURLsChanged: { [weak self] urls in
            guard let self else { return }
            self.leftPane.setDimmedFileURLs([])
            self.rightPane.setDimmedFileURLs([])
            if !urls.isEmpty { self.targetPane().setDimmedFileURLs(urls) }
        },
        onFeedbackExpired: { [weak self] in self?.clearClipboardFeedback() }
    )
    private let applicationOpener: any ApplicationOpening
    private lazy var openFileCoordinator = OpenFileCoordinator(accessPolicy: accessPolicy) { [weak self] fileURL, applicationURL in
        if let applicationURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
                if let error {
                    self?.showError(message: "Could Not Open File".localized, detail: error.localizedDescription)
                }
            }
        } else {
            _ = self?.applicationOpener.open(fileURL)
        }
    }
    private let fileSizeService: any FileSizeResolving
    private let readOnlyViewerService: any ViewerContentLoading
    private let diagnosticsExporter: any DiagnosticsExporting
    private let fileOperationPresentationCoordinator = FileOperationPresentationCoordinator()
    private let stagingCleanupFactory: (@escaping () -> [URL]) -> StagingCleanupService
    private let scratchCleanupFactory: (@escaping () -> [URL]) -> ScratchFolderCleanupService
    private lazy var scratchDirectoryCoordinator = ScratchDirectoryWorkflowCoordinator(
        settings: settings,
        accessPolicy: accessPolicy,
        folderSelection: authorizedFolderSelection,
        cleanupFactory: scratchCleanupFactory,
        activeRoots: { [weak self] in
            guard let self else { return [] }
            return [self.leftPane.currentDirectory, self.rightPane.currentDirectory]
        }
    )
    /// The sole authority for command availability and target resolution.
    private let commandRouter = MainCommandRouter()
    private lazy var commandCoordinator = MainWindowCommandCoordinator(
        router: commandRouter,
        inputs: .init(
            activePaneID: { [weak self] in self?.activePaneID ?? .left },
            pane: { [weak self] paneID in self?.commandSnapshot(for: paneID) ?? Self.emptyCommandSnapshot(for: paneID) },
            isSinglePaneMode: { [weak self] in self?.isSinglePaneMode == true },
            isFileOperationActive: { [weak self] in self?.isFileOperationActive == true },
            hasUndoRecovery: { [weak self] in self?.undoRecovery?.eligibility() == .eligible },
            canAccess: { [accessPolicy] in accessPolicy.canAccess($0) }
        ),
        output: { [weak self] in self?.handle($0) }
    )
    private lazy var previewCoordinator = PreviewCoordinator(accessPolicy: accessPolicy, probe: fileSystemProbe)
    private lazy var navigationCoordinator = NavigationCoordinator(probe: fileSystemProbe)

    private let rootSplitView = NSSplitView()
    private let contentSplitView = NSSplitView()
    private let paneSplitView = MinimalDividerSplitView()
    private let mainStack = NSView()
    weak var toolbarSearchField: NSSearchField?
    private weak var sidebarToolbarItem: NSToolbarItem?
    private var didSetInitialSplitPositions = false
    private var keyEventMonitor: Any?
    private var flagsChangedEventMonitor: Any?
    private var sidebarMinWidthConstraint: NSLayoutConstraint?
    private var sidebarMaxWidthConstraint: NSLayoutConstraint?
    private let sidebarLayoutCoordinator = SidebarLayoutCoordinator()
    private let terminalLayoutCoordinator = TerminalLayoutCoordinator()
    private let terminalPresentationCoordinator: TerminalPresentationCoordinator
    private var terminalHeightConstraint: NSLayoutConstraint?
    private var isSidebarInstalled: Bool { sidebarLayoutCoordinator.isInstalled }
    private var isTerminalInstalled: Bool { terminalLayoutCoordinator.isInstalled }
    private var isSinglePaneMode = false
    private let fileOperationCoordinator = FileOperationCoordinator()
    private lazy var operationCoordinator = MainWindowFileOperationCoordinator(
        fileOperations: fileOperations,
        state: fileOperationCoordinator,
        accessPolicy: accessPolicy,
        presenter: self,
        onActivityChanged: { [weak self] in self?.refreshCommandAvailability() },
        onDefaultRefresh: { [weak self] in self?.refreshBothPanes() },
        onResult: { [weak self] name, result in self?.recordOperationSummary(name, result: result) },
        onOperationStarted: { [weak self] in self?.clearClipboardFeedback() }
    )
    var quickLookPreviewURL: NSURL?
    private var quickLookProbeGeneration = 0
    private lazy var readOnlyViewerCoordinator = ReadOnlyViewerPresentationCoordinator(service: readOnlyViewerService)
    private var fileOperationPreviousWindowTitle: String?
    private var isFileOperationActive: Bool { operationCoordinator.isActive }
    private var undoRecovery: FileOperationRecovery? { operationCoordinator.undoRecovery }

    var compositionForTesting: (
        paneFileSystems: [any FileSystemServicing],
        panePolicyIdentities: [ObjectIdentifier],
        sidebarPolicyIdentity: ObjectIdentifier,
        sidebarDirectorySizing: any DirectorySizing,
        terminalPolicyIdentity: ObjectIdentifier,
        folderAccessGrants: any FolderAccessGrantProviding
    ) {
        (
            [leftPane.viewModel.fileSystemForCompositionTesting, rightPane.viewModel.fileSystemForCompositionTesting],
            [leftPane.viewModel.accessPolicyIdentityForCompositionTesting, rightPane.viewModel.accessPolicyIdentityForCompositionTesting],
            sidebar.accessPolicyIdentityForCompositionTesting,
            sidebar.directorySizingForCompositionTesting,
            terminal.accessPolicyIdentityForCompositionTesting,
            authorizedFolderSelection.grantServiceForCompositionTesting
        )
    }

    var activePaneID: PaneID = .left {
        didSet {
            guard oldValue != activePaneID else { return }
            updateActivePane()
        }
    }

    init(
        settings: SettingsService,
        dependencies: MainWindowDependencies,
        workflowDependencies: MainWindowWorkflowDependencies,
        sandboxRootEnsurer: @escaping () -> Void = ExperimentalFlags.ensureAppSandboxRootExists
    ) {
        self.settings = settings
        self.accessPolicy = dependencies.accessPolicy
        self.fileSystem = dependencies.paneFileSystem
        self.authorizedFolderSelection = dependencies.authorizedFolderSelection
        self.symbolicLinkResolver = dependencies.symbolicLinkResolver
        self.sandboxRootEnsurer = sandboxRootEnsurer
        self.workflows = workflowDependencies
        self.fileOperations = dependencies.fileOperations
        self.fileSystemProbe = dependencies.fileSystemProbe
        self.recentLocations = dependencies.recentLocations
        self.bookmarkService = dependencies.bookmarks
        self.volumeDiscovery = dependencies.volumeDiscovery
        self.directorySizing = dependencies.directorySizing
        self.thumbnailLoader = dependencies.thumbnailLoader
        self.standardFolderAccess = dependencies.standardFolderAccess
        self.folderAccessGrants = dependencies.folderAccessGrants
        self.applicationOpener = dependencies.applicationOpener
        self.fileSizeService = dependencies.fileSize
        self.readOnlyViewerService = dependencies.readOnlyViewer
        self.diagnosticsExporter = dependencies.diagnosticsExporter
        self.terminal = TerminalViewController(terminalService: dependencies.terminalState, processFactory: dependencies.terminalProcessFactory, accessPolicy: dependencies.accessPolicy, liquidGlassStyle: LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled))
        self.terminalPresentationCoordinator = TerminalPresentationCoordinator(service: dependencies.terminalState)
        self.stagingCleanupFactory = dependencies.stagingCleanup
        self.scratchCleanupFactory = dependencies.scratchCleanup
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func startTerminalSessionForCompositionTesting() {
        terminal.startSessionIfAllowed()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = liquidGlassStyle.windowBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        sandboxRootEnsurer()
        #endif
        buildLayout()
        bindPaneCallbacks()
        volumeChangeMonitor.onVolumesChanged = { [weak self] change in
            guard let self else { return }
            self.sidebar.refreshDevices()
            let panes = [self.leftPane, self.rightPane]
            let directories = panes.map(\.currentDirectory)
            let generation = self.workflows.paneSynchronization.beginVolumeProbe()
            Task { [weak self] in
                guard let self else { return }
                let actions = await self.navigationCoordinator.volumeChangeActions(for: directories, change: change)
                // Ignore a completion that belongs to an older mount event.
                guard self.workflows.paneSynchronization.acceptsVolumeProbe(
                    generation,
                    originalDirectories: directories,
                    currentDirectories: panes.map(\.currentDirectory)
                ) else { return }
                for (pane, action) in zip(panes, actions) where action == .fallBack {
                    pane.fallBackIfCurrentDirectoryIsUnavailable()
                }
                for (pane, action) in zip(panes, actions) where action == .revalidate {
                    pane.revalidateAfterVolumeChange()
                }
            }
        }
        updateActivePane()
        leftPane.loadDirectory()
        rightPane.loadDirectory()
        presentStartupAccessRecoveryIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyEventMonitors()
        view.window?.makeFirstResponder(targetPane().tableView)
    }

    deinit {
        terminal.stopRunningCommand()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
        if let flagsChangedEventMonitor {
            NSEvent.removeMonitor(flagsChangedEventMonitor)
        }
    }

    private func buildLayout() {
        rootSplitView.isVertical = true
        rootSplitView.dividerStyle = .paneSplitter
        rootSplitView.delegate = self
        rootSplitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootSplitView)
        NSLayoutConstraint.activate([
            rootSplitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            rootSplitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            rootSplitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            rootSplitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])

        mainStack.translatesAutoresizingMaskIntoConstraints = false
        rootSplitView.addArrangedSubview(mainStack)
        addChild(sidebar)
        mainStack.widthAnchor.constraint(greaterThanOrEqualToConstant: SidebarMetrics.contentMinWidth).isActive = true
        sidebarMinWidthConstraint = sidebar.view.widthAnchor.constraint(greaterThanOrEqualToConstant: SidebarMetrics.minWidth)
        sidebarMaxWidthConstraint = sidebar.view.widthAnchor.constraint(lessThanOrEqualToConstant: SidebarMetrics.maxWidth)
        if settings.isSidebarVisible {
            installSidebarView()
        }

        contentSplitView.isVertical = false
        contentSplitView.dividerStyle = .paneSplitter
        contentSplitView.delegate = self
        contentSplitView.translatesAutoresizingMaskIntoConstraints = false
        commandBar.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addSubview(contentSplitView)
        mainStack.addSubview(commandBar)
        NSLayoutConstraint.activate([
            contentSplitView.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            contentSplitView.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            contentSplitView.topAnchor.constraint(equalTo: mainStack.topAnchor),
            contentSplitView.bottomAnchor.constraint(equalTo: commandBar.topAnchor),
            commandBar.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            commandBar.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            commandBar.bottomAnchor.constraint(equalTo: mainStack.bottomAnchor),
            commandBar.heightAnchor.constraint(equalToConstant: 50)
        ])

        paneSplitView.isVertical = true
        paneSplitView.dividerStyle = .thin
        paneSplitView.delegate = self
        addChild(leftPane)
        addChild(rightPane)
        leftPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rightPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        contentSplitView.addArrangedSubview(paneSplitView)
        setSinglePaneMode(settings.defaultSinglePaneMode, focusPane: activePaneID)

        addChild(terminal)
        if settings.experimentalTerminalEnabled && settings.defaultTerminalVisible {
            installTerminalPanel(showWarning: true)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didSetInitialSplitPositions, view.bounds.width > 0, view.bounds.height > 0 else { return }
        didSetInitialSplitPositions = true
        applySidebarSplitPosition()
        if !isSinglePaneMode {
            paneSplitView.setPosition(max(260, paneSplitView.bounds.width / 2), ofDividerAt: 0)
        }
        if isTerminalInstalled {
            contentSplitView.setPosition(max(220, contentSplitView.bounds.height - 180), ofDividerAt: 0)
        }
    }

    /// A denied saved startup folder is intentionally not opened or prompted
    /// for automatically. The person can opt in to the picker from this
    /// recovery alert, which creates a fresh folder grant.
    private func presentStartupAccessRecoveryIfNeeded() {
        let recoveries: [(PaneID, StartupDirectoryResolution)] = [
            (.left, leftStartupResolution),
            (.right, rightStartupResolution)
        ]
        guard let recovery = recoveries.first(where: { $0.1.needsAccessRecovery }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Startup Folder Access Needed".localized
        alert.informativeText = "PulseFiles could not access %@, so this pane opened a safe default instead. Choose Folder… to grant access deliberately.".localized(with: recovery.1.requestedDirectory.path)
        alert.addButton(withTitle: "Choose Folder…".localized)
        alert.addButton(withTitle: "Not Now".localized)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            if recovery.0 == .left {
                self?.leftPane.chooseDirectoryForAccessRecovery()
            } else {
                self?.rightPane.chooseDirectoryForAccessRecovery()
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func bindPaneCallbacks() {
        [leftPane, rightPane].forEach {
            $0.navigationDelegate = self
            $0.commandDelegate = self
            $0.presentationDelegate = self
        }
        terminal.workingDirectoryProvider = { [weak self] in
            guard let self else { return ExperimentalFlags.appSandboxRoot }
            return self.terminalPresentationCoordinator.workingDirectory(activePaneURL: self.targetPane().currentDirectory, accessPolicy: self.accessPolicy)
        }
        terminal.isShellInteractionAllowedProvider = { [weak self] in
            guard let self else { return false }
            return self.settings.experimentalTerminalEnabled && self.settings.hasAcknowledgedTerminalWarning
        }
        sidebar.onOpenLocation = { [weak self] url, useInactive in self?.targetPane(useInactive: useInactive).navigate(to: url) }
        commandBar.onAction = { [weak self] action in self?.performCommand(MainCommand(commandBarAction: action), entrySurface: .commandBar) }
    }

    func targetPane(useInactive: Bool = false) -> FilePaneViewController {
        let paneID = useInactive ? activePaneID.opposite : activePaneID
        return paneID == .left ? leftPane : rightPane
    }

    private func focusPane(_ paneID: PaneID) {
        if activePaneID == paneID {
            targetPane().makeTableFirstResponder()
            return
        }
        activePaneID = paneID
        if isSinglePaneMode { rebuildPaneArrangement() }
    }

    func openAcceptedFolderFromExternalEvent(_ directory: URL) {
        targetPane().navigate(to: directory)
    }

    private func updateActivePane() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Active pane switched: pane=\(String(describing: activePaneID)); directory=\(DiagnosticLogger.sanitizedPath(targetPane().currentDirectory))")
        leftPane.setActive(activePaneID == .left)
        rightPane.setActive(activePaneID == .right)
        terminal.suggestedWorkingDirectory = targetPane().currentDirectory
        toolbarSearchField?.stringValue = targetPane().viewModel.searchQuery
        sidebar.showSelection(targetPane().selectedItems)
        refreshCommandAvailability()
        if view.window?.firstResponder !== toolbarSearchField {
            targetPane().makeTableFirstResponder()
        }
    }

    private func performCommand(_ command: MainCommand, from pane: PaneID? = nil, entrySurface: MainCommandEntrySurface = .menu) {
        if let pane { activePaneID = pane }
        DiagnosticLogger.log(.info, category: "MainWindow", "Command execution requested: command=\(command); activePane=\(String(describing: activePaneID))")
        commandCoordinator.perform(command, from: entrySurface)
    }

    private func performRoutedPaneCallback(_ command: MainCommand, from pane: PaneID, action: () -> Void) {
        activePaneID = pane
        let route = commandCoordinator.route(command, from: .paneCallback)
        if case let .disabled(disabledCommand, reason) = route {
            presentDisabledCommandFeedback(command: disabledCommand, reason: reason)
        } else {
            action()
        }
    }

    func handle(_ route: MainCommandRoute) {
        switch route {
        case let .disabled(command, reason):
            presentDisabledCommandFeedback(command: command, reason: reason)
            return
        case let .activePane(command, pane, _), let .focusedItem(command, pane, _), let .symbolicLink(command, pane, _):
            activePaneID = pane
            dispatchTypedUIEvent(command)
        case let .crossPane(command, sourcePane, _, _, _):
            activePaneID = sourcePane
            dispatchTypedUIEvent(command)
        case let .switchPane(pane):
            activePaneID = pane
            if isSinglePaneMode { rebuildPaneArrangement(); updateActivePane() }
        case let .dualPane(command, activePane, _):
            activePaneID = activePane
            dispatchTypedUIEvent(command)
        case let .enabled(command):
            dispatchTypedUIEvent(command)
        }
    }

    private func dispatchTypedUIEvent(_ command: MainCommand) {
        switch command {
        case .open:
            targetPane().openFocusedItem()
        case .viewer:
            showViewerForFocusedItem()
        case .openWith:
            presentOpenWithApplicationPicker()
        case .quickLook:
            showQuickLookForFocusedItem()
        case .newFile:
            promptForNewFile()
        case .newFolder:
            promptForNewFolder()
        case .rename:
            beginInlineRename()
        case .batchRename:
            promptForBatchRename()
        case .createArchive:
            promptForArchiveCreation()
        case .extractArchive:
            confirmArchiveExtraction()
        case .duplicate:
            confirmDuplicateSelectedItems()
        case .getInfo:
            showInfoForFocusedItem()
        case .selectAll:
            targetPane().selectAllItems()
        case .deselectAll:
            targetPane().deselectAllItems()
        case .selectByPattern:
            presentPatternSelection(mutation: .select)
        case .deselectByPattern:
            presentPatternSelection(mutation: .deselect)
        case .selectSameExtension:
            targetPane().applySameExtensionMarks(.select)
        case .deselectSameExtension:
            targetPane().applySameExtensionMarks(.deselect)
        case .invertSelection:
            targetPane().invertSelection()
        case .undo:
            undoLastOperation()
        case .copy:
            copySelectedItems()
        case .move:
            moveSelectedItems()
        case .copyToClipboard:
            writeSelectionToClipboard(operation: .copy)
        case .cutToClipboard:
            writeSelectionToClipboard(operation: .move)
        case .pasteFromClipboard:
            pasteClipboardItems()
        case .trash:
            confirmDeleteSelectedItems()
        case .refresh:
            clearClipboardFeedback()
            targetPane().loadDirectory()
        case .reveal:
            if let item = targetPane().focusedItem {
                applicationOpener.reveal([item.url])
            }
        case .toggleHiddenFiles:
            targetPane().toggleHiddenFiles()
        case .sortByName:
            targetPane().setSort(.name)
        case .sortByExtension:
            targetPane().setSort(.extension)
        case .sortByKind:
            targetPane().setSort(.kind)
        case .sortBySize:
            targetPane().setSort(.size)
        case .sortByModified:
            targetPane().setSort(.modified)
        case .sortByCreated:
            targetPane().setSort(.created)
        case .sortByAdded:
            targetPane().setSort(.added)
        case .sortByAccessed:
            targetPane().setSort(.accessed)
        case .sortAscending:
            targetPane().setSort(targetPane().sortDescriptor.key, ascending: true)
        case .sortDescending:
            targetPane().setSort(targetPane().sortDescriptor.key, ascending: false)
        case .toggleTerminal:
            toggleTerminal()
        case .toggleSidebar:
            toggleSidebar()
        case .togglePaneLayout:
            setSinglePaneMode(!isSinglePaneMode, focusPane: activePaneID)
        case .newTab:
            targetPane().newTab()
        case .closeTab:
            targetPane().closeTab()
        case .nextTab:
            targetPane().nextTab()
        case .previousTab:
            targetPane().previousTab()
        case .back:
            targetPane().goBack()
        case .forward:
            targetPane().goForward()
        case .parent:
            targetPane().goParent()
        case .goToFolder:
            promptForGoToFolder()
        case .quickLocations:
            presentQuickLocations()
        case .searchDescendants:
            promptForDescendantSearch()
        case .home, .downloads, .applications:
            targetPane().navigate(to: navigationCoordinator.standardLocation(for: command))
        case .scratchDirectory:
            performScratchDirectoryCommand(useInactive: NSEvent.modifierFlags.contains(.option))
        case .switchPane:
            assertionFailure("Switch-pane commands must execute a typed switchPane route")
        case .swapPanes:
            swapPaneLogicalStates()
        case .syncOppositePane:
            synchronizeOppositePane()
        case .revealInOppositePane:
            revealFocusedItemInOppositePane()
        case .followSymbolicLink:
            followFocusedSymbolicLink()
        case .cancelOperation:
            cancelActiveFileOperation()
        case .debugLogs:
            presentDebugLogs(nil)
        case .exportDiagnostics:
            exportDiagnostics()
        }
    }

    private func presentDisabledCommandFeedback(command: MainCommand, reason: MainCommandRoutingDisabledReason) {
        DiagnosticLogger.log(.warning, category: "MainWindow", "Command rejected: command=\(command); reason=\(reason)")
        let feedback = workflows.commandPresentation.feedback(
            for: reason,
            parentRowFocused: targetPane().focusedDestination == .parent
        )
        showError(message: feedback.message.localized, detail: feedback.detail.localized)
    }

    private func promptForArchiveCreation() {
        let pane = targetPane()
        workflows.archiveAndRename.promptForArchiveCreation(sources: pane.selectedItems.map(\.url), directory: pane.currentDirectory, presenter: self)
    }

    private func confirmArchiveExtraction() {
        let pane = targetPane()
        workflows.archiveAndRename.confirmArchiveExtraction(archive: pane.focusedItem?.url, directory: pane.currentDirectory, presenter: self)
    }

    private func promptForBatchRename() {
        workflows.archiveAndRename.promptForBatchRename(sources: targetPane().selectedItems.map(\.url), presenter: self)
    }

    private func presentQuickLocations() {
        let active = targetPane()
        let opposite = isSinglePaneMode ? nil : targetPane(useInactive: true).currentDirectory
        Task { [weak self] in
            guard let self else { return }
            let volumes = await volumeDiscovery.mountedVolumes()
            let entries = QuickLocationAssembler.assemble(
                activeDirectory: active.currentDirectory,
                history: active.viewModel.navigationHistory,
                bookmarks: bookmarkService.load(),
                recent: recentLocations.locations,
                volumes: volumes,
                scratchDirectory: settings.scratchDirectory,
                oppositeDirectory: opposite,
                canAccess: { self.accessPolicy.canAccess($0) },
                exists: { FileManager.default.fileExists(atPath: $0.path) }
            )
            guard active === self.targetPane() else { return }
            let controller = QuickLocationsViewController(entries: entries, allowsInactivePane: !isSinglePaneMode)
            let popover = workflows.auxiliaryPanels.showQuickLocations(controller, relativeTo: active.view)
            controller.onCancel = { [weak popover] in popover?.performClose(nil) }
            controller.onActivate = { [weak self, weak popover] entry, inactive in
                guard let self, self.accessPolicy.canAccess(entry.url) else { NSSound.beep(); return }
                self.targetPane(useInactive: inactive).navigate(to: entry.url)
                popover?.performClose(nil)
            }
        }
    }

    private func presentPatternSelection(mutation: MarkMutation) {
        let pane = targetPane()
        let controller = PatternSelectionPanelController(items: pane.viewModel.visibleItems, mutation: mutation)
        controller.onApply = { [weak pane] matches in
            pane?.applyMarks(matchingURLs: matches, mutation: mutation)
        }
        workflows.auxiliaryPanels.showPatternSelection(controller, window: view.window) { [weak self, weak pane] in
            if let pane { self?.view.window?.makeFirstResponder(pane.tableView) }
        }
    }

    private func swapPaneLogicalStates() {
        let leftState = leftPane.logicalStateSnapshot()
        let rightState = rightPane.logicalStateSnapshot()
        do {
            // Validate both destinations before changing either pane.
            try accessPolicy.validateAccess(to: leftState.currentDirectory)
            try accessPolicy.validateAccess(to: rightState.currentDirectory)
            try leftPane.restoreLogicalState(rightState)
            try rightPane.restoreLogicalState(leftState)
            toolbarSearchField?.stringValue = targetPane().viewModel.searchQuery
            view.window?.makeFirstResponder(targetPane().tableView)
        } catch {
            showError(message: "Could Not Swap Panes".localized, detail: error.localizedDescription)
        }
    }

    private func synchronizeOppositePane() {
        let source = targetPane()
        let destination = targetPane(useInactive: true)
        let synchronizedDirectory = workflows.paneSynchronization.synchronizedDirectory(from: source.currentDirectory)
        do {
            try accessPolicy.validateAccess(to: synchronizedDirectory)
            destination.preparePendingSelection(source.focusedItem?.url)
            destination.navigate(to: synchronizedDirectory)
            view.window?.makeFirstResponder(source.tableView)
        } catch {
            showError(message: "Could Not Sync Opposite Pane".localized, detail: error.localizedDescription)
        }
    }

    private func revealFocusedItemInOppositePane() {
        guard let item = targetPane().focusedItem else { return }
        let source = targetPane()
        let destination = targetPane(useInactive: true)
        let plan = workflows.paneSynchronization.revealPlan(for: item.url)
        do {
            try accessPolicy.validateAccess(to: plan.item)
            try accessPolicy.validateAccess(to: plan.directory)
            destination.preparePendingSelection(plan.item)
            destination.navigate(to: plan.directory)
            view.window?.makeFirstResponder(source.tableView)
        } catch {
            showError(message: "Could Not Reveal Item".localized, detail: error.localizedDescription)
        }
    }

    private func followFocusedSymbolicLink() {
        guard let item = targetPane().focusedItem, item.isSymbolicLink else { return }
        do {
            let target = try symbolicLinkResolver.resolveOneHop(item.url)
            try accessPolicy.validateAccess(to: target)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                targetPane().navigate(to: target)
            } else {
                targetPane().preparePendingSelection(target)
                targetPane().navigate(to: target.deletingLastPathComponent())
            }
        } catch {
            showError(message: "Could Not Follow Symbolic Link".localized, detail: error.localizedDescription)
        }
    }

    private func performScratchDirectoryCommand(useInactive: Bool) {
        scratchDirectoryCoordinator.perform(useInactive: useInactive, presenter: self)
    }

    func navigateToScratchDirectory(_ directory: URL, useInactive: Bool) {
        toolbarSearchField?.stringValue = ""
        let pane = targetPane(useInactive: useInactive)
        pane.setSearchQuery("")
        pane.navigate(to: directory)
        view.window?.makeFirstResponder(pane.tableView)
    }

    func scratchDirectoryConfigurationDidChange() { sidebar.refresh() }

    override func keyDown(with event: NSEvent) {
        if !handleGlobalKeyDown(event) {
            targetPane().handleKeyDown(event)
        }
    }

    private func installKeyEventMonitors() {
        guard keyEventMonitor == nil, flagsChangedEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.updateCommandBarModifierState(from: event)
            return self.handleGlobalKeyDown(event) ? nil : event
        }
        flagsChangedEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.updateCommandBarModifierState(from: event)
            return event
        }
    }

    private func updateCommandBarModifierState(from event: NSEvent) {
        commandBar.setShiftPressed(event.modifierFlags.contains(.shift))
    }

    private func handleGlobalKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            if isFileOperationActive {
                performCommand(.cancelOperation, entrySurface: .keyboard)
            } else {
                view.window?.makeFirstResponder(targetPane().tableView)
            }
            return true
        }
        let isTextInputFocused = isTextInputFirstResponder
        let paneNavigationModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if !isTextInputFocused, paneNavigationModifiers.isEmpty, (123...126).contains(event.keyCode) {
            // Arrow navigation belongs to the active pane even when pane
            // activation left a non-table view in the responder chain. Route
            // it explicitly rather than relying on AppKit to eventually send
            // the event to the active pane's table view.
            targetPane().handleKeyDown(event)
            return true
        }
        if !isTextInputFocused,
           paneNavigationModifiers.isEmpty,
           event.keyCode == 36,
           targetPane().focusedDestination == .parent {
            // Return normally routes through the global `.open` command. The
            // synthetic `..` row intentionally has no focused URL, so let the
            // pane handle it before command routing translates that safe state
            // into "no focused item."
            targetPane().openFocusedItem()
            return true
        }
        if let routedCommand = commandRouter.commandForKeyDown(event, isTextInputFocused: isTextInputFocused) {
            performCommand(routedCommand, entrySurface: .keyboard)
            return true
        }
        if commandRouter.shouldConsumeUnmappedKeyDown(keyCode: event.keyCode, isTextInputFocused: isTextInputFocused) {
            return true
        }
        return false
    }

    private var isTextInputFirstResponder: Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        return firstResponder is NSTextView || firstResponder is NSTextField
    }

    private func showQuickLookForFocusedItem() {
        guard let item = targetPane().focusedItem else {
            showError(message: "Nothing Selected".localized, detail: "Select one item to preview with Quick Look.".localized)
            return
        }

        quickLookProbeGeneration += 1
        let generation = quickLookProbeGeneration
        Task { [weak self] in
            guard let self else { return }
            let availability = await self.previewCoordinator.availability(of: item.url)
            guard generation == self.quickLookProbeGeneration,
                  self.targetPane().focusedItem?.url == item.url else { return }
            if case .blocked(let detail) = availability {
                self.showError(message: "Preview Blocked".localized, detail: detail)
                return
            }
            guard availability == .available else {
                self.showError(message: "Preview Unavailable".localized, detail: "The selected item is unavailable or no longer exists.".localized)
                return
            }
            self.quickLookPreviewURL = item.url as NSURL
            guard let panel = QLPreviewPanel.shared() else {
                self.showError(message: "Preview Unavailable".localized, detail: "Quick Look is not available for this item.".localized)
                return
            }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showViewerForFocusedItem() {
        guard let item = targetPane().focusedItem, !item.isDirectory else {
            showError(message: "Nothing Selected".localized, detail: "Select a file to view.".localized)
            return
        }
        readOnlyViewerCoordinator.present(item.url)
    }
}

extension MainWindowViewController {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search".localized
            item.searchField.placeholderString = "Search active pane".localized
            item.searchField.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.searchField)
            item.searchField.target = self
            item.searchField.action = #selector(toolbarSearchChanged(_:))
            item.searchField.sendsSearchStringImmediately = true
            toolbarSearchField = item.searchField
            return item
        case .toggleTerminal:
            let item = toolbarItem(itemIdentifier, label: "Beta Terminal".localized, symbol: "terminal", action: #selector(toolbarToggleTerminal(_:)))
            item.view?.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.terminalToggle)
            return item
        case .toggleSidebar:
            let item = toolbarItem(itemIdentifier, label: "Sidebar".localized, symbol: "sidebar.right", action: #selector(toolbarToggleSidebar(_:)))
            item.view?.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.sidebarToggle)
            sidebarToolbarItem = item
            updateSidebarToolbarItem()
            return item
        case .viewOptions:
            return toolbarItem(itemIdentifier, label: "View".localized, symbol: "line.3.horizontal.decrease.circle", action: #selector(toolbarViewOptions(_:)))
        case .settings:
            return toolbarItem(itemIdentifier, label: "Settings".localized, symbol: "gearshape", action: #selector(toolbarSettings(_:)))
        default:
            return nil
        }
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .toggleSidebar {
            updateSidebarToolbarItem()
        }
        return true
    }

    @objc private func toolbarBack(_ sender: Any?) {
        performCommand(.back, entrySurface: .toolbar)
    }

    @objc private func toolbarForward(_ sender: Any?) {
        performCommand(.forward, entrySurface: .toolbar)
    }

    @objc private func toolbarToggleTerminal(_ sender: Any?) {
        performCommand(.toggleTerminal, entrySurface: .toolbar)
    }

    @objc private func toolbarToggleSidebar(_ sender: Any?) {
        performCommand(.toggleSidebar, entrySurface: .toolbar)
    }

    @objc func toolbarSettings(_ sender: Any?) {
        presentSettings(sender)
    }

    func reloadSettingsFromJSONIfChanged() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Settings reload requested from JSON")
        settings.importJSONIfChanged()
        applySettingsChanges()
        (workflows.auxiliaryPanels.settingsWindowController?.contentViewController as? SettingsViewController)?.reloadFromSettings()
    }

    private func presentSettings(_ sender: Any?) {
        reloadSettingsFromJSONIfChanged()
        let cleanupService = stagingCleanupFactory { [weak self] in
            guard let self else { return [] }
            return [self.leftPane.currentDirectory, self.rightPane.currentDirectory]
        }
        let scratchCleanupService = scratchCleanupFactory { [weak self] in
                guard let self else { return [] }
                return [self.leftPane.currentDirectory, self.rightPane.currentDirectory]
            }
        let controller = SettingsViewController(settings: settings, stagingCleanupService: cleanupService, scratchCleanupService: scratchCleanupService, accessPolicy: accessPolicy, accessGrantService: folderAccessGrants, standardFolderAccess: standardFolderAccess, folderSelection: authorizedFolderSelection)
        controller.onOpenScratchDirectory = { [weak self] url in
            self?.targetPane().navigate(to: url)
        }
        controller.onChange = { [weak self] in self?.applySettingsChanges() }
        controller.onMaintenanceCleanup = { [weak self] in self?.refreshBothPanes() }
        controller.onScratchCleanupResult = { [weak self] result, operationName in
            self?.refreshBothPanes()
            self?.presentFileOperationResult(result, operationName: operationName)
        }
        workflows.auxiliaryPanels.showSettings(controller, sender: sender)
    }


    private func presentDebugLogs(_ sender: Any?) {
        workflows.auxiliaryPanels.showDebugLogs(DebugLogViewController(liquidGlassStyle: liquidGlassStyle), sender: sender)
    }


    private func applySettingsChanges() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Applying settings changes: terminalEnabled=\(settings.experimentalTerminalEnabled); terminalDefaultVisible=\(settings.defaultTerminalVisible); sidebarDefaultVisible=\(settings.defaultSidebarVisible); singlePane=\(settings.defaultSinglePaneMode)")
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        let style = liquidGlassStyle
        view.layer?.backgroundColor = style.windowBackground.cgColor
        view.window?.backgroundColor = style.windowBackground
        setSidebarVisible(settings.defaultSidebarVisible)
        let shouldShowTerminal = settings.experimentalTerminalEnabled && settings.defaultTerminalVisible
        if !settings.experimentalTerminalEnabled {
            removeTerminalPanel()
            settings.isTerminalVisible = false
        } else if shouldShowTerminal != isTerminalInstalled {
            if shouldShowTerminal {
                installTerminalPanel(showWarning: true)
            } else {
                removeTerminalPanel()
                settings.isTerminalVisible = false
            }
        }
        setSinglePaneMode(settings.defaultSinglePaneMode, focusPane: activePaneID)
        leftPane.setShowsHiddenFiles(settings.showHiddenFilesByDefault)
        rightPane.setShowsHiddenFiles(settings.showHiddenFilesByDefault)
        leftPane.setSortDescriptor(settings.sortDescriptor(for: .left))
        rightPane.setSortDescriptor(settings.sortDescriptor(for: .right))
        leftPane.viewModel.setQuickSearchOptions(matchMode: settings.quickSearchMatchMode, presentation: settings.quickSearchPresentation)
        rightPane.viewModel.setQuickSearchOptions(matchMode: settings.quickSearchMatchMode, presentation: settings.quickSearchPresentation)
        #if DEBUG
        sandboxRootEnsurer()
        #endif
        if accessPolicy.isEnabled {
            if !accessPolicy.canAccess(leftPane.currentDirectory) {
                leftPane.navigate(to: accessPolicy.validatedDirectory(leftPane.currentDirectory))
            }
            if !accessPolicy.canAccess(rightPane.currentDirectory) {
                rightPane.navigate(to: accessPolicy.validatedDirectory(rightPane.currentDirectory))
            }
        }
        sidebar.refreshAppearance(style: style)
        commandBar.refreshAppearance(style: style)
        terminal.refreshAppearance(style: style)
        view.layoutSubtreeIfNeeded()
        applySidebarSplitPosition()
        leftPane.refreshAppearance(style: style)
        rightPane.refreshAppearance(style: style)
    }

    @objc private func toolbarViewOptions(_ sender: Any?) {
        let menu = buildViewOptionsMenu()
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
        }
    }

    private func buildViewOptionsMenu() -> NSMenu {
        let menu = NSMenu(title: "View Options".localized)
        menu.addItem(menuItem("Refresh".localized, action: #selector(menuRefresh(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Show Hidden Files".localized, action: #selector(menuToggleHiddenFiles(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(menuItem("Sort by Name".localized, action: #selector(menuSortByName(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Extension".localized, action: #selector(menuSortByExtension(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Kind".localized, action: #selector(menuSortByKind(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Size".localized, action: #selector(menuSortBySize(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Modified".localized, action: #selector(menuSortByModified(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Created".localized, action: #selector(menuSortByCreated(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Added".localized, action: #selector(menuSortByAdded(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Accessed".localized, action: #selector(menuSortByAccessed(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(menuItem("Ascending".localized, action: #selector(menuSortAscending(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Descending".localized, action: #selector(menuSortDescending(_:)), key: "", modifiers: []))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func toolbarSearchChanged(_ sender: NSSearchField) {
        targetPane().setSearchQuery(sender.stringValue)
    }

    private func setSinglePaneMode(_ singlePane: Bool, focusPane: PaneID) {
        isSinglePaneMode = singlePane
        activePaneID = focusPane
        rebuildPaneArrangement()
        updateActivePane()
        NSApp.mainMenu?.update()
    }

    private func rebuildPaneArrangement() {
        leftPane.setHasOppositePane(!isSinglePaneMode)
        rightPane.setHasOppositePane(!isSinglePaneMode)
        paneSplitView.arrangedSubviews.forEach { subview in
            paneSplitView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        if isSinglePaneMode {
            paneSplitView.addArrangedSubview(targetPane().view)
        } else {
            paneSplitView.addArrangedSubview(leftPane.view)
            paneSplitView.addArrangedSubview(rightPane.view)
        }

        view.layoutSubtreeIfNeeded()
        if !isSinglePaneMode, paneSplitView.bounds.width > 0 {
            paneSplitView.setPosition(max(260, paneSplitView.bounds.width / 2), ofDividerAt: 0)
        }
    }

    private func toggleTerminal() {
        DiagnosticLogger.log(.info, category: "Terminal", "Terminal toggle requested: currentlyVisible=\(isTerminalInstalled); experimentEnabled=\(settings.experimentalTerminalEnabled)")
        terminalPresentationCoordinator.synchronize(installed: isTerminalInstalled)
        switch terminalPresentationCoordinator.toggle(isEnabled: settings.experimentalTerminalEnabled) {
        case .hide:
            removeTerminalPanel()
            settings.isTerminalVisible = false
            view.window?.makeFirstResponder(targetPane().tableView)
        case .disabled:
            DiagnosticLogger.log(.warning, category: "Terminal", "Terminal toggle denied because experimental terminal is disabled")
            showTerminalDisabledAlert()
        case .show:
            installTerminalPanel(showWarning: true)
            settings.isTerminalVisible = true
            terminal.suggestedWorkingDirectory = terminalPresentationCoordinator.workingDirectory(
                activePaneURL: targetPane().currentDirectory,
                accessPolicy: accessPolicy
            )
            view.layoutSubtreeIfNeeded()
            contentSplitView.setPosition(max(220, contentSplitView.bounds.height - 180), ofDividerAt: 0)
            terminal.focusCommandField()
        }
    }

    private func installTerminalPanel(showWarning: Bool = false) {
        guard !isTerminalInstalled else { return }
        DiagnosticLogger.log(.info, category: "Terminal", "Installing terminal panel: showWarning=\(showWarning)")
        if showWarning {
            showFirstUseTerminalWarningIfNeeded()
        }
        terminalLayoutCoordinator.install(terminal, in: contentSplitView, heightConstraint: &terminalHeightConstraint)
    }

    private func showTerminalDisabledAlert() {
        let alert = NSAlert()
        alert.messageText = "Beta Terminal is disabled".localized
        alert.informativeText = "Enable the Beta Terminal in Settings before opening it. Shell commands can modify or delete files.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showFirstUseTerminalWarningIfNeeded() {
        let warningState = terminalPresentationCoordinator.warningState(settings: settings, accessPolicy: accessPolicy)
        guard !warningState.isAcknowledged else { return }

        let alert = NSAlert()
        alert.messageText = warningState.messageText
        alert.informativeText = warningState.informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I Understand".localized)
        let acknowledgementResponse = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let presentation = terminalPresentationCoordinator
        let settings = settings
        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                presentation.acknowledgeWarningIfNeeded(response: response.rawValue, acknowledgementResponse: acknowledgementResponse, settings: settings)
                self?.terminal.startSessionIfAllowed()
                self?.terminal.focusCommandField()
            }
        } else {
            let response = alert.runModal()
            presentation.acknowledgeWarningIfNeeded(response: response.rawValue, acknowledgementResponse: acknowledgementResponse, settings: settings)
            terminal.startSessionIfAllowed()
        }
    }

    private func removeTerminalPanel() {
        guard isTerminalInstalled else { return }
        DiagnosticLogger.log(.info, category: "Terminal", "Removing terminal panel")
        terminalLayoutCoordinator.remove(terminal, from: contentSplitView, heightConstraint: terminalHeightConstraint)
    }

    private func toggleSidebar() {
        setSidebarVisible(!isSidebarInstalled)
    }

    private func setSidebarVisible(_ visible: Bool) {
        if visible {
            installSidebarView()
        } else {
            persistSidebarWidthFromSplitPosition()
            removeSidebarView()
        }
        settings.isSidebarVisible = visible
        view.layoutSubtreeIfNeeded()
        if visible {
            applySidebarSplitPosition()
        }
        updateSidebarToolbarItem()
    }

    private func applySidebarSplitPosition() {
        guard isSidebarInstalled, rootSplitView.arrangedSubviews.count > 1 else { return }
        sidebarLayoutCoordinator.applyPersistedWidth(settings.sidebarWidth, sidebarView: sidebar.view, in: rootSplitView)
    }

    private func installSidebarView() {
        guard !isSidebarInstalled else { return }
        sidebarLayoutCoordinator.install(sidebar.view, in: rootSplitView, constraints: [sidebarMinWidthConstraint, sidebarMaxWidthConstraint].compactMap { $0 })
    }

    private func removeSidebarView() {
        guard isSidebarInstalled else { return }
        sidebarLayoutCoordinator.remove(sidebar.view, from: rootSplitView, constraints: [sidebarMinWidthConstraint, sidebarMaxWidthConstraint].compactMap { $0 })
    }

    private func persistSidebarWidthFromSplitPosition() {
        guard let width = sidebarLayoutCoordinator.persistedWidth(sidebarView: sidebar.view, in: rootSplitView) else { return }
        settings.sidebarWidth = width
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        sidebarLayoutCoordinator.clampedWidth(width)
    }

    private func updateSidebarToolbarItem() {
        guard let item = sidebarToolbarItem else { return }
        let label = isSidebarInstalled ? "Hide Sidebar".localized : "Show Sidebar".localized
        let symbol = isSidebarInstalled ? "sidebar.right" : "sidebar.left"
        item.label = label
        item.paletteLabel = "Sidebar".localized
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    }

    private func promptForNewFolder() {
        view.window?.makeFirstResponder(nil)
        workflows.fileCreation.promptForFolder(in: targetPane().currentDirectory, window: view.window) { [weak self] name, directory in
            guard let self else { return }
            self.startCreationOperation(named: "Create Folder".localized, directory: directory) { [workflows = self.workflows] _ in
                try await workflows.fileCreation.createFolder(named: name, in: directory)
            }
        }
    }

    private func promptForNewFile() {
        view.window?.makeFirstResponder(nil)
        workflows.fileCreation.promptForFile(in: targetPane().currentDirectory, window: view.window) { [weak self] name, directory in
            guard let self else { return }
            self.startCreationOperation(named: "Create File".localized, directory: directory) { [workflows = self.workflows] _ in
                try await workflows.fileCreation.createFile(named: name, in: directory)
            }
        }
    }

    private func startCreationOperation(named operationName: String, directory: URL, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult) {
        startFileOperation(named: operationName, operation: operation, completion: { [weak self] result in
            guard let self, let destination = result.completedItems.first else { return }
            let pane = [self.leftPane, self.rightPane].first { $0.currentDirectory == directory } ?? self.targetPane()
            pane.viewModel.invalidateCurrentDirectorySnapshot(); pane.loadDirectory(selecting: destination)
        })
    }

    private func presentOpenWithApplicationPicker() {
        let files = targetPane().selectedItems.filter { !$0.isDirectory }.map(\.url)
        workflows.openWith.present(files: files, presenter: self) { [weak self] file, application in self?.openFile(file, with: application) }
    }

    private func openFile(_ fileURL: URL, with applicationURL: URL?) {
        do {
            try openFileCoordinator.open(fileURL, with: applicationURL)
        } catch {
            showError(message: "Could Not Open File".localized, detail: error.localizedDescription)
        }
    }

    private func promptForGoToFolder() {
        view.window?.makeFirstResponder(nil)
        let pane = targetPane()
        workflows.goToFolder.prompt(currentDirectory: pane.currentDirectory, presenter: self) { [weak self, weak pane] url in
            guard let self, let pane, self.targetPane() === pane else { return }; pane.navigate(to: url)
        }
    }

    private func promptForDescendantSearch() {
        let pane = targetPane()
        let root = pane.focusedItem.flatMap { $0.isDirectory ? $0.url : nil } ?? pane.currentDirectory
        workflows.search.prompt(root: root, presenter: self) { [weak self] action, item in self?.routeSearchResultAction(action, item: item, root: root) }
    }

    private func routeSearchResultAction(_ action: DescendantSearchResultsViewController.Action, item: DescendantSearchItem, root: URL) {
        do {
            let destination = try workflows.search.route(action, item: item, root: root)
            switch action {
            case .open: NSWorkspace.shared.open(item.url)
            case .reveal: NSWorkspace.shared.activateFileViewerSelecting([item.url])
            case .navigate:
                try accessPolicy.validateAccess(to: destination); targetPane().preparePendingSelection(item.url); targetPane().navigate(to: destination)
            }
        } catch { showError(message: "Search Result Unavailable".localized, detail: error.localizedDescription) }
    }

    private func beginInlineRename() {
        guard targetPane().beginInlineRename() else {
            showError(message: "Nothing Selected".localized, detail: "Select one item to rename.".localized)
            return
        }
    }

    private func rename(item: FileItem, to rawName: String) {
        startFileOperation(named: "Rename".localized, captureRecovery: true) { [fileOperations] progressHandler in
            try await fileOperations.rename(item.url, to: rawName, progressHandler: progressHandler)
        } refresh: { [weak self] result in
            self?.refreshPanesAfterRename(sourceURL: item.url, result: result)
        }
    }

    private func confirmDuplicateSelectedItems() {
        let urls = targetPane().selectedItems.map(\.url)
        guard !urls.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more items to duplicate.".localized)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Duplicate %d Item(s)?".localized(with: urls.count)
        alert.informativeText = "Copies are created in the current folder. Existing names are preserved by adding a copy suffix.".localized
        alert.addButton(withTitle: "Duplicate".localized)
        alert.addButton(withTitle: "Cancel".localized)
        let performDuplicate: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.startFileOperation(named: "Duplicate".localized, captureRecovery: true) { [fileOperations] progressHandler in
                try await fileOperations.copy(
                    FileOperationRequest(sources: urls, destinationDirectory: urls[0].deletingLastPathComponent()),
                    conflictHandler: { _ in .keepBoth },
                    progressHandler: progressHandler
                )
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: performDuplicate)
        } else {
            performDuplicate(alert.runModal())
        }
    }

    private func showInfoForFocusedItem() {
        guard let item = targetPane().focusedItem else {
            showError(message: "Nothing Selected".localized, detail: "Select one item to view its information.".localized)
            return
        }

        let accessPolicy = accessPolicy
        let fileSizeService = fileSizeService
        Task { [weak self] in
            do {
                let details = try await Task.detached(priority: .userInitiated) {
                    try accessPolicy.withValidatedAccess(to: item.url) {
                        let values = try item.url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                        let size = try fileSizeService.size(of: item.url)
                        return (isDirectory: values.isDirectory == true, modificationDate: values.contentModificationDate, size: size)
                    }
                }.value
                guard let self else { return }

                let size = ByteCountFormatter.string(fromByteCount: details.size, countStyle: .file)
                let modified = details.modificationDate.map {
                    DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
                } ?? "Unknown".localized
                let alert = NSAlert()
                alert.messageText = item.displayName
                alert.informativeText = "Location: %@\nKind: %@\nSize: %@\nModified: %@".localized(
                    with: item.url.path,
                    details.isDirectory ? "Folder".localized : "File".localized,
                    size,
                    modified
                )
                alert.addButton(withTitle: "OK".localized)
                if let window = self.view.window {
                    alert.beginSheetModal(for: window) { _ in }
                } else {
                    _ = alert.runModal()
                }
            } catch {
                self?.showError(message: "Information Unavailable".localized, detail: error.localizedDescription)
            }
        }
    }

    private func confirmDeleteSelectedItems() {
        let items = targetPane().selectedItems
        guard !items.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more items to delete.".localized)
            return
        }
        let permanentlyDelete = settings.permanentlyDeleteInsteadOfTrash
        let operationName = permanentlyDelete ? "Permanently Delete".localized : "Move to Trash".localized
        let confirmButtonTitle = permanentlyDelete ? "Permanently Delete".localized : "Move to Trash".localized
        if !permanentlyDelete && settings.confirmDeleteOperations == false {
            delete(items: items, permanently: permanentlyDelete)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = deleteConfirmationMessage(permanently: permanentlyDelete, itemCount: items.count)
        alert.informativeText = deleteConfirmationDetail(
            permanently: permanentlyDelete,
            urls: items.map(\.url)
        )
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel — Keep Items".localized)

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else {
                DiagnosticLogger.log(.info, category: "MainWindow", "User cancelled destructive confirmation: operation=\(operationName); itemCount=\(items.count)")
                return
            }
            self.delete(items: items, permanently: permanentlyDelete)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func delete(items: [FileItem], permanently: Bool) {
        let operationName = permanently ? "Permanently Delete".localized : "Move to Trash".localized
        // Every mutation invalidates an older recovery. Permanent deletion
        // deliberately supplies no recovery, while Trash may supply one.
        startFileOperation(named: operationName, captureRecovery: true) { [fileOperations] progressHandler in
            if permanently {
                return try await fileOperations.delete(items.map(\.url), progressHandler: progressHandler)
            }
            return try await fileOperations.trash(items.map(\.url), progressHandler: progressHandler)
        }
    }

    private func copySelectedItems() {
        performFileTransfer(kind: "Copy".localized, shouldConfirm: settings.confirmCopyOperations, captureRecovery: true) { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.copy(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func moveSelectedItems() {
        performFileTransfer(kind: "Move".localized, shouldConfirm: settings.confirmMoveOperations, captureRecovery: true) { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.move(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func performFileTransfer(
        kind: String,
        shouldConfirm: Bool,
        captureRecovery: Bool = false,
        operation: @escaping (FileOperationRequest, @escaping FileConflictHandler, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more items in the active pane.".localized)
            return
        }
        performFileTransfer(
            kind: kind,
            sources: sources,
            destinationDirectory: targetPane(useInactive: true).currentDirectory,
            shouldConfirm: shouldConfirm,
            captureRecovery: captureRecovery,
            operation: operation
        )
    }

    private func performFileTransfer(
        kind: String,
        sources: [URL],
        destinationDirectory: URL,
        shouldConfirm: Bool,
        captureRecovery: Bool = false,
        operation: @escaping (FileOperationRequest, @escaping FileConflictHandler, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) {
        do {
            try operationCoordinator.transfer(
                named: kind,
                sources: sources,
                destinationDirectory: destinationDirectory,
                shouldConfirm: shouldConfirm,
                captureRecovery: captureRecovery,
                operation: operation
            )
        } catch {
            showError(message: "Cannot Complete \(kind)".localized, detail: error.localizedDescription)
        }
    }


    private func writeSelectionToClipboard(operation: FileClipboard.Operation) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more items in the active pane.".localized)
            return
        }
        do {
            try clipboardSession.write(sources, operation: operation)
            showClipboardFeedback(for: operation, itemCount: sources.count)
        } catch {
            showError(message: "Could Not Use Clipboard".localized, detail: error.localizedDescription)
        }
    }

    private func pasteClipboardItems() {
        guard let payload = clipboardSession.payload(), !payload.urls.isEmpty else {
            clearClipboardFeedback()
            showError(message: "Clipboard Is Empty".localized, detail: "Copy or cut one or more files before pasting.".localized)
            return
        }
        do {
            let prepared = try workflows.fileTransfer.pasteOperation(payload: payload, destination: targetPane().currentDirectory)
            let shouldConfirm = payload.operation == .copy ? settings.confirmCopyOperations : settings.confirmMoveOperations
            performFileTransfer(kind: prepared.0, sources: payload.urls, destinationDirectory: prepared.1.destinationDirectory,
                                shouldConfirm: shouldConfirm, captureRecovery: true) { _, conflicts, progress in
                try await prepared.2(conflicts, progress)
            }
        } catch { showError(message: "Could Not Paste".localized, detail: error.localizedDescription) }
    }

    private func showClipboardFeedback(for operation: FileClipboard.Operation, itemCount: Int) {
        let verb = operation == .copy ? "Copied".localized : "Cut".localized
        let itemLabel = itemCount == 1 ? "item".localized : "items".localized
        commandBar.setTransientStatus("%@ %d %@".localized(with: verb, itemCount, itemLabel))
    }

    private func clearClipboardFeedback() {
        clipboardSession.clear()
        leftPane.setDimmedFileURLs([])
        rightPane.setDimmedFileURLs([])
        if !isFileOperationActive {
            commandBar.clearOperationStatus()
        }
    }

    private func transferDroppedItems(_ urls: [URL], to destinationDirectory: URL, copy: Bool) {
        guard !urls.isEmpty else { return }
        DiagnosticLogger.log(.info, category: "MainWindow", "Resolved dropped-item transfer: operation=\(copy ? "copy" : "move"); itemCount=\(urls.count); destination=\(DiagnosticLogger.sanitizedPath(destinationDirectory))")
        guard !isFileOperationActive else {
            showError(message: "Operation in Progress".localized, detail: "Wait for the current file operation to finish before starting another file-changing action.".localized)
            return
        }
        Task { [weak self, fileSystemProbe] in
            guard let self else { return }
            do {
                let generation = try await self.clipboardSession.validateDrop(sources: urls, destination: destinationDirectory, probe: fileSystemProbe)
                guard self.clipboardSession.isCurrentDrop(generation: generation) else { return }
                self.beginDroppedItemTransfer(urls, destinationDirectory: destinationDirectory, copy: copy)
            } catch { self.showError(message: "Could Not Accept Drop".localized, detail: error.localizedDescription) }
        }
    }

    private func beginDroppedItemTransfer(_ urls: [URL], destinationDirectory: URL, copy: Bool) {
        let kind = copy ? "Copy".localized : "Move".localized
        let shouldConfirm = copy ? settings.confirmCopyOperations : settings.confirmMoveOperations
        performFileTransfer(kind: kind, sources: urls, destinationDirectory: destinationDirectory, shouldConfirm: shouldConfirm, captureRecovery: true) { [fileOperations] request, conflicts, progress in
            if copy {
                return try await fileOperations.copy(request, conflictHandler: conflicts, progressHandler: progress)
            }
            return try await fileOperations.move(request, conflictHandler: conflicts, progressHandler: progress)
        }
    }

    func presentFileOperationConfirmation(
        operationName: String,
        urls: [URL],
        destinationDirectory: URL?,
        confirmButtonTitle: String,
        completion: @escaping () -> Void
    ) {
        let alert = fileOperationPresentationCoordinator.confirmation(
            operationName: operationName, urls: urls, destinationDirectory: destinationDirectory,
            confirmButtonTitle: confirmButtonTitle
        ).makeAlert()

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else {
                DiagnosticLogger.log(.info, category: "MainWindow", "User cancelled destructive confirmation: operation=\(operationName); itemCount=\(urls.count)")
                return
            }
            completion()
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func deleteConfirmationMessage(permanently: Bool, itemCount: Int) -> String {
        let itemLabel = itemCount == 1 ? "1 Item".localized : "%d Items".localized(with: itemCount)
        return permanently
            ? "Permanently Delete %@?".localized(with: itemLabel)
            : "Move %@ to Trash?".localized(with: itemLabel)
    }

    private func deleteConfirmationDetail(permanently: Bool, urls: [URL]) -> String {
        let operationName = permanently ? "Permanent Delete".localized : "Move to Trash".localized
        var lines = [
            "Operation: %@".localized(with: operationName),
            permanently
                ? "This permanently deletes the selected item(s) immediately. This cannot be undone from the Trash.".localized
                : "This moves the selected item(s) to the macOS Trash. You can restore them from the Trash until it is emptied.".localized,
            "",
            "Items:".localized
        ]
        let visibleNames = urls.prefix(8).map { "- \($0.lastPathComponent)" }
        lines.append(contentsOf: visibleNames)
        if urls.count > visibleNames.count {
            lines.append("- ...and %d more".localized(with: urls.count - visibleNames.count))
        }
        return lines.joined(separator: "\n")
    }

    private func undoLastOperation() { operationCoordinator.undo() }

    private func cancelActiveFileOperation() { operationCoordinator.cancel() }

    private func detachActiveFileOperation() { operationCoordinator.detach() }

    private func recordOperationSummary(_ operation: String, result: FileOperationResult) {
        recentOperationSummaries.append(DiagnosticOperationSummary(operation: operation, result: result))
        if recentOperationSummaries.count > 20 { recentOperationSummaries.removeFirst(recentOperationSummaries.count - 20) }
    }

    private func exportDiagnostics() {
        let window = view.window
        let request = AuthorizedFolderSelectionCoordinator.Request(
            prompt: "Export".localized,
            message: "Choose a folder for a local support bundle. Review it before attaching it to a support request.".localized,
            acceptsExistingAccessibleURL: true,
            presentingWindow: window
        )
        authorizedFolderSelection.selectFolder(for: request) { [weak self] result in
            guard let self else { return }
            guard case .success(let destination) = result else {
                if case .failure(let failure) = result { FolderAccessFailurePresenter.present(failure, in: window) }
                return
            }
            do {
                try fileOperationPresentationCoordinator.exportDiagnostics(
                    to: destination, exporter: diagnosticsExporter,
                    entries: DiagnosticLogService.shared.entries,
                    operationSummaries: recentOperationSummaries,
                    reveal: NSWorkspace.shared.activateFileViewerSelecting
                )
            } catch {
                showError(message: "Could Not Export Diagnostics".localized, detail: error.localizedDescription)
            }
        }
    }

    private func startFileOperation(named operationName: String, captureRecovery: Bool = false, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult, refresh: ((FileOperationResult) -> Void)? = nil, completion: ((FileOperationResult) -> Void)? = nil) {
        operationCoordinator.start(named: operationName, captureRecovery: captureRecovery, operation: operation, refresh: refresh, completion: completion)
    }

    func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String) {
        fileOperationProgressWindowController.update(operationName: operationName, progress: progress)
        view.window?.title = "\(operationName): \(progress.currentItemName)"
    }

    func beginFileOperationProgress(named operationName: String) {
        fileOperationPreviousWindowTitle = view.window?.title
        fileOperationProgressWindowController.show(operationName: operationName, parentWindow: view.window)
    }

    func endFileOperationProgress() {
        if let title = fileOperationPreviousWindowTitle { view.window?.title = title }
        fileOperationPreviousWindowTitle = nil
        fileOperationProgressWindowController.dismiss()
    }

    func showFileOperationCancellationPending() { fileOperationProgressWindowController.showCancellationPending() }

    func presentFileOperationError(operationName: String, detail: String) {
        showError(message: "Could Not %@ Items".localized(with: operationName), detail: detail)
    }

    func presentUndoUnavailable() {
        showError(message: "Undo Unavailable".localized, detail: "The last operation cannot be safely undone.".localized)
    }

    func presentDetachedFileOperationWarning() {
        showAlert(
            message: "Operation Needs Verification".localized,
            detail: "PulseFiles stopped waiting because the operation made no progress or did not finish after cancellation. Its final filesystem state is unknown; refresh and verify the affected items before trying another operation.".localized,
            style: .warning
        )
    }

    static func operationResultPresentation(_ result: FileOperationResult, operationName: String) -> (message: String, detail: String, style: NSAlert.Style)? {
        FileOperationCoordinator.resultPresentation(result, operationName: operationName)
    }

    func presentFileOperationResult(_ result: FileOperationResult, operationName: String) {
        guard let presentation = fileOperationPresentationCoordinator.result(result, operationName: operationName) else { return }
        showAlert(message: presentation.message, detail: presentation.detail, style: presentation.style)
    }

    private func refreshCommandAvailability() {
        let state = commandCoordinator.state()
        commandBar.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSControl }.forEach { control in
            guard let rawValue = control.identifier?.rawValue, let action = CommandBarAction(rawValue: rawValue) else { return }
            if case .disabled = commandRouter.route(MainCommand(commandBarAction: action), in: state) {
                control.isEnabled = false
            } else {
                control.isEnabled = true
            }
        }
        NSApp.mainMenu?.update()
    }

    @MainActor
    func resolveFileOperationConflict(destination: URL, operationName: String) async -> FileConflictResolution {
        let conflict = fileOperationPresentationCoordinator.conflict(
            destination: destination, operationName: operationName,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        let alert = conflict.0.makeAlert()

        let applyToRemaining = NSButton(checkboxWithTitle: "Apply this choice to remaining conflicts".localized, target: nil, action: nil)
        applyToRemaining.setAccessibilityLabel("Apply this conflict choice to remaining conflicts".localized)
        alert.accessoryView = applyToRemaining

        guard let window = view.window else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                let apply = applyToRemaining.state == .on
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: apply ? .applyToRemainingKeepBoth : .keepBoth)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: apply ? .applyToRemainingReplace : .replace)
                case .alertThirdButtonReturn:
                    continuation.resume(returning: apply ? .applyToRemainingSkip : .skip)
                default:
                    continuation.resume(returning: .cancel)
                }
            }
        }
    }

    private func refreshBothPanes() {
        refreshPanes([leftPane, rightPane])
    }

    private func refreshPanes(_ panes: [FilePaneViewController]) {
        panes.forEach { $0.viewModel.invalidateCurrentDirectorySnapshot() }
        panes.forEach { $0.loadDirectory() }
    }

    private func refreshPanesAfterRename(sourceURL: URL, result: FileOperationResult) {
        let panes = [leftPane, rightPane]
        let plan = RenamePaneRefreshPlan(currentDirectories: panes.map(\.currentDirectory), sourceURL: sourceURL)
        guard let renamedURL = result.completedItems.first else {
            refreshPanes(panes)
            return
        }

        // Capture this before loads complete: their selection notifications must
        // not change which pane receives keyboard focus after the rename.
        let activePaneID = self.activePaneID
        let renamedPanes = plan.renamedPaneIndexes.map { panes[$0] }
        let genericPanes = plan.genericRefreshPaneIndexes.map { panes[$0] }
        refreshPanes(genericPanes)
        guard !renamedPanes.isEmpty else { return }

        var remainingReloads = renamedPanes.count
        renamedPanes.forEach { pane in
            pane.viewModel.invalidateCurrentDirectorySnapshot()
            pane.loadDirectory(selecting: renamedURL) { [weak self] in
                guard let self else { return }
                remainingReloads -= 1
                guard remainingReloads == 0 else { return }
                self.activePaneID = activePaneID
                self.view.window?.makeFirstResponder(self.pane(for: activePaneID).tableView)
            }
        }
    }

    func pane(for paneID: PaneID) -> FilePaneViewController {
        paneID == .left ? leftPane : rightPane
    }

    private func showError(message: String, detail: String) {
        showAlert(message: message, detail: detail, style: .warning)
    }

    private func showAlert(message: String, detail: String, style: NSAlert.Style) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(message: message, detail: detail, style: style)
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

extension MainWindowViewController {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        switch splitView {
        case rootSplitView:
            return SidebarMetrics.contentMinWidth
        case paneSplitView:
            return 260
        case contentSplitView:
            return 220
        default:
            return proposedMinimumPosition
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        switch splitView {
        case rootSplitView:
            if !isSidebarInstalled {
                return splitView.bounds.width
            }
            return max(SidebarMetrics.contentMinWidth, splitView.bounds.width - SidebarMetrics.minWidth)
        case paneSplitView:
            return max(260, splitView.bounds.width - 260)
        case contentSplitView:
            return max(220, splitView.bounds.height - 120)
        default:
            return proposedMaximumPosition
        }
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView, splitView === rootSplitView else { return }
        persistSidebarWidthFromSplitPosition()
    }
}

extension MainWindowViewController {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === workflows.auxiliaryPanels.settingsWindowController?.window {
            view.window?.makeKeyAndOrderFront(nil)
        } else if window === workflows.auxiliaryPanels.debugLogWindowController?.window {
            view.window?.makeKeyAndOrderFront(nil)
        }
    }
}



extension MainWindowViewController {
    var workflowWindow: NSWindow? { view.window }

    func startWorkflowOperation(named name: String, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult) { startFileOperation(named: name, operation: operation) }
    func presentWorkflowError(message: String, detail: String) { showError(message: message, detail: detail) }
    func workflowFailed(message: String, detail: String) { showError(message: message, detail: detail) }
    func resolveWorkflowConflict(destination: URL, operationName: String) async -> FileConflictResolution { await resolveFileOperationConflict(destination: destination, operationName: operationName) }

    @objc func menuNewFile(_ sender: Any?) { performCommand(.newFile) }
    @objc func menuNewFolder(_ sender: Any?) { performCommand(.newFolder) }
    @objc func menuRename(_ sender: Any?) { performCommand(.rename) }
    @objc func menuBatchRename(_ sender: Any?) { performCommand(.batchRename) }
    @objc func menuCreateArchive(_ sender: Any?) { performCommand(.createArchive) }
    @objc func menuExtractArchive(_ sender: Any?) { performCommand(.extractArchive) }
    @objc func menuDuplicate(_ sender: Any?) { performCommand(.duplicate) }
    @objc func menuGetInfo(_ sender: Any?) { performCommand(.getInfo) }
    @objc func menuSelectAll(_ sender: Any?) { performCommand(.selectAll) }
    @objc func menuDeselectAll(_ sender: Any?) { performCommand(.deselectAll) }
    @objc func menuSelectByPattern(_ sender: Any?) { performCommand(.selectByPattern) }
    @objc func menuDeselectByPattern(_ sender: Any?) { performCommand(.deselectByPattern) }
    @objc func menuSelectSameExtension(_ sender: Any?) { performCommand(.selectSameExtension) }
    @objc func menuDeselectSameExtension(_ sender: Any?) { performCommand(.deselectSameExtension) }
    @objc func menuInvertSelection(_ sender: Any?) { performCommand(.invertSelection) }
    @objc func menuUndo(_ sender: Any?) { performCommand(.undo) }
    @objc func menuOpenWith(_ sender: Any?) { performCommand(.openWith) }
    @objc func menuViewer(_ sender: Any?) { performCommand(.viewer) }
    @objc func menuCopy(_ sender: Any?) { performCommand(.copy) }
    @objc func menuMove(_ sender: Any?) { performCommand(.move) }
    @objc func menuCopyToClipboard(_ sender: Any?) { performCommand(.copyToClipboard) }
    @objc func menuCutToClipboard(_ sender: Any?) { performCommand(.cutToClipboard) }
    @objc func menuPasteFromClipboard(_ sender: Any?) { performCommand(.pasteFromClipboard) }
    @objc func menuMoveToTrash(_ sender: Any?) { performCommand(.trash) }
    @objc func menuRefresh(_ sender: Any?) { performCommand(.refresh) }
    @objc func menuReveal(_ sender: Any?) { performCommand(.reveal) }
    @objc func menuToggleHiddenFiles(_ sender: Any?) { performCommand(.toggleHiddenFiles) }
    @objc func menuPresentationList(_ sender: Any?) { targetPane().setPresentationMode(.list) }
    @objc func menuPresentationBrief(_ sender: Any?) { targetPane().setPresentationMode(.brief) }
    @objc func menuPresentationGallery(_ sender: Any?) { targetPane().setPresentationMode(.gallery) }
    @objc func menuSortByName(_ sender: Any?) { performCommand(.sortByName) }
    @objc func menuSortByExtension(_ sender: Any?) { performCommand(.sortByExtension) }
    @objc func menuSortByKind(_ sender: Any?) { performCommand(.sortByKind) }
    @objc func menuSortBySize(_ sender: Any?) { performCommand(.sortBySize) }
    @objc func menuSortByModified(_ sender: Any?) { performCommand(.sortByModified) }
    @objc func menuSortByCreated(_ sender: Any?) { performCommand(.sortByCreated) }
    @objc func menuSortByAdded(_ sender: Any?) { performCommand(.sortByAdded) }
    @objc func menuSortByAccessed(_ sender: Any?) { performCommand(.sortByAccessed) }
    @objc func menuSortAscending(_ sender: Any?) { performCommand(.sortAscending) }
    @objc func menuSortDescending(_ sender: Any?) { performCommand(.sortDescending) }
    @objc func menuToggleTerminal(_ sender: Any?) { performCommand(.toggleTerminal) }
    @objc func menuToggleSidebar(_ sender: Any?) { performCommand(.toggleSidebar) }
    @objc func menuTogglePaneLayout(_ sender: Any?) { performCommand(.togglePaneLayout) }
    @objc func menuNewTab(_ sender: Any?) { performCommand(.newTab) }
    @objc func menuCloseTab(_ sender: Any?) { performCommand(.closeTab) }
    @objc func menuNextTab(_ sender: Any?) { performCommand(.nextTab) }
    @objc func menuPreviousTab(_ sender: Any?) { performCommand(.previousTab) }
    @objc func menuBack(_ sender: Any?) { performCommand(.back) }
    @objc func menuForward(_ sender: Any?) { performCommand(.forward) }
    @objc func menuParent(_ sender: Any?) { performCommand(.parent) }
    @objc func menuGoToFolder(_ sender: Any?) { performCommand(.goToFolder) }
    @objc func menuQuickLocations(_ sender: Any?) { performCommand(.quickLocations) }
    @objc func menuSearchDescendants(_ sender: Any?) { performCommand(.searchDescendants) }
    @objc func menuHome(_ sender: Any?) { performCommand(.home) }
    @objc func menuDownloads(_ sender: Any?) { performCommand(.downloads) }
    @objc func menuApplications(_ sender: Any?) { performCommand(.applications) }
    @objc func menuScratchDirectory(_ sender: Any?) { performCommand(.scratchDirectory) }
    @objc func menuSwitchPane(_ sender: Any?) { performCommand(.switchPane) }
    @objc func menuFocusLeftPane(_ sender: Any?) { focusPane(.left) }
    @objc func menuFocusRightPane(_ sender: Any?) { focusPane(.right) }
    @objc func menuSwapPanes(_ sender: Any?) { performCommand(.swapPanes) }
    @objc func menuSyncOppositePane(_ sender: Any?) { performCommand(.syncOppositePane) }
    @objc func menuRevealInOppositePane(_ sender: Any?) { performCommand(.revealInOppositePane) }
    @objc func menuFollowSymbolicLink(_ sender: Any?) { performCommand(.followSymbolicLink) }
    @objc func menuCancelOperation(_ sender: Any?) { performCommand(.cancelOperation) }
    @objc func menuSettings(_ sender: Any?) { presentSettings(sender) }
    @objc func menuShowDebugLogs(_ sender: Any?) { performCommand(.debugLogs) }
    @objc func menuExportDiagnostics(_ sender: Any?) { performCommand(.exportDiagnostics) }
    @objc func menuEditSettingsJSON(_ sender: Any?) {
        do {
            let url = try settings.writeSettingsJSON()
            NSWorkspace.shared.open(url)
        } catch {
            showError(message: "Could Not Open Settings JSON".localized, detail: error.localizedDescription)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let routedCommand = MainCommand(menuAction: menuItem.action)
        let routeAllowsCommand: Bool = {
            guard let routedCommand else { return true }
            if case .disabled = commandCoordinator.route(routedCommand, from: .menu) { return false }
            return true
        }()
        if menuItem.action == #selector(menuUndo(_:)) {
            menuItem.title = undoRecovery?.undoTitle.localized ?? "Undo".localized
        }
        if menuItem.action == #selector(menuToggleSidebar(_:)) {
            menuItem.state = isSidebarInstalled ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuToggleTerminal(_:)) {
            menuItem.state = isTerminalInstalled ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuTogglePaneLayout(_:)) {
            menuItem.title = isSinglePaneMode ? "Use Dual Pane".localized : "Use Single Pane".localized
            menuItem.state = isSinglePaneMode ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuToggleHiddenFiles(_:)) {
            menuItem.state = targetPane().showsHiddenFiles ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuMoveToTrash(_:)) {
            menuItem.title = settings.permanentlyDeleteInsteadOfTrash ? "Permanently Delete".localized : "Move to Trash".localized
        }
        let sort = targetPane().sortDescriptor
        if menuItem.action == #selector(menuSortByName(_:)) {
            menuItem.state = sort.key == .name ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortByExtension(_:)) {
            menuItem.state = sort.key == .extension ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortByKind(_:)) {
            menuItem.state = sort.key == .kind ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortBySize(_:)) {
            menuItem.state = sort.key == .size ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortByModified(_:)) {
            menuItem.state = sort.key == .modified ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortByCreated(_:)) { menuItem.state = sort.key == .created ? .on : .off; return routeAllowsCommand }
        if menuItem.action == #selector(menuSortByAdded(_:)) { menuItem.state = sort.key == .added ? .on : .off; return routeAllowsCommand }
        if menuItem.action == #selector(menuSortByAccessed(_:)) { menuItem.state = sort.key == .accessed ? .on : .off; return routeAllowsCommand }
        if menuItem.action == #selector(menuSortAscending(_:)) {
            menuItem.state = sort.ascending ? .on : .off
            return routeAllowsCommand
        }
        if menuItem.action == #selector(menuSortDescending(_:)) {
            menuItem.state = sort.ascending ? .off : .on
            return routeAllowsCommand
        }
        menuItem.state = .off
        return routeAllowsCommand
    }

    private func commandSnapshot(for paneID: PaneID) -> MainWindowCommandCoordinator.PaneSnapshot {
        let pane = pane(for: paneID)
        return .init(
            id: paneID, currentDirectory: pane.currentDirectory,
            selectedURLs: pane.selectedItems.map(\.url), focusedURL: pane.focusedItem?.url,
            focusedItemIsSymbolicLink: pane.focusedItem?.isSymbolicLink == true,
            tabCount: pane.viewModel.tabs.count
        )
    }

    private static func emptyCommandSnapshot(for paneID: PaneID) -> MainWindowCommandCoordinator.PaneSnapshot {
        .init(id: paneID, currentDirectory: URL(fileURLWithPath: "/", isDirectory: true), selectedURLs: [], focusedURL: nil, focusedItemIsSymbolicLink: false, tabCount: 1)
    }

    /// Exposes the exact route used by UI validation to the in-process AppKit
    /// harness without exposing mutable pane state.
    func commandRouteForValidation(_ command: MainCommand) -> MainCommandRoute {
        commandCoordinator.route(command, from: .menu)
    }
}

private extension MainCommand {
    init?(menuAction: Selector?) {
        guard let menuAction else { return nil }
        switch menuAction {
        case #selector(MainWindowViewController.menuViewer(_:)): self = .viewer
        case #selector(MainWindowViewController.menuNewFile(_:)): self = .newFile
        case #selector(MainWindowViewController.menuNewFolder(_:)): self = .newFolder
        case #selector(MainWindowViewController.menuRename(_:)): self = .rename
        case #selector(MainWindowViewController.menuBatchRename(_:)): self = .batchRename
        case #selector(MainWindowViewController.menuCreateArchive(_:)): self = .createArchive
        case #selector(MainWindowViewController.menuExtractArchive(_:)): self = .extractArchive
        case #selector(MainWindowViewController.menuDuplicate(_:)): self = .duplicate
        case #selector(MainWindowViewController.menuGetInfo(_:)): self = .getInfo
        case #selector(MainWindowViewController.menuSelectAll(_:)): self = .selectAll
        case #selector(MainWindowViewController.menuDeselectAll(_:)): self = .deselectAll
        case #selector(MainWindowViewController.menuSelectByPattern(_:)): self = .selectByPattern
        case #selector(MainWindowViewController.menuDeselectByPattern(_:)): self = .deselectByPattern
        case #selector(MainWindowViewController.menuSelectSameExtension(_:)): self = .selectSameExtension
        case #selector(MainWindowViewController.menuDeselectSameExtension(_:)): self = .deselectSameExtension
        case #selector(MainWindowViewController.menuInvertSelection(_:)): self = .invertSelection
        case #selector(MainWindowViewController.menuUndo(_:)): self = .undo
        case #selector(MainWindowViewController.menuOpenWith(_:)): self = .openWith
        case #selector(MainWindowViewController.menuCopy(_:)): self = .copy
        case #selector(MainWindowViewController.menuMove(_:)): self = .move
        case #selector(MainWindowViewController.menuCopyToClipboard(_:)): self = .copyToClipboard
        case #selector(MainWindowViewController.menuCutToClipboard(_:)): self = .cutToClipboard
        case #selector(MainWindowViewController.menuPasteFromClipboard(_:)): self = .pasteFromClipboard
        case #selector(MainWindowViewController.menuMoveToTrash(_:)): self = .trash
        case #selector(MainWindowViewController.menuRefresh(_:)): self = .refresh
        case #selector(MainWindowViewController.menuReveal(_:)): self = .reveal
        case #selector(MainWindowViewController.menuToggleHiddenFiles(_:)): self = .toggleHiddenFiles
        case #selector(MainWindowViewController.menuSortByName(_:)): self = .sortByName
        case #selector(MainWindowViewController.menuSortByExtension(_:)): self = .sortByExtension
        case #selector(MainWindowViewController.menuSortByKind(_:)): self = .sortByKind
        case #selector(MainWindowViewController.menuSortBySize(_:)): self = .sortBySize
        case #selector(MainWindowViewController.menuSortByModified(_:)): self = .sortByModified
        case #selector(MainWindowViewController.menuSortByCreated(_:)): self = .sortByCreated
        case #selector(MainWindowViewController.menuSortByAdded(_:)): self = .sortByAdded
        case #selector(MainWindowViewController.menuSortByAccessed(_:)): self = .sortByAccessed
        case #selector(MainWindowViewController.menuSortAscending(_:)): self = .sortAscending
        case #selector(MainWindowViewController.menuSortDescending(_:)): self = .sortDescending
        case #selector(MainWindowViewController.menuToggleTerminal(_:)): self = .toggleTerminal
        case #selector(MainWindowViewController.menuToggleSidebar(_:)): self = .toggleSidebar
        case #selector(MainWindowViewController.menuTogglePaneLayout(_:)): self = .togglePaneLayout
        case #selector(MainWindowViewController.menuNewTab(_:)): self = .newTab
        case #selector(MainWindowViewController.menuCloseTab(_:)): self = .closeTab
        case #selector(MainWindowViewController.menuNextTab(_:)): self = .nextTab
        case #selector(MainWindowViewController.menuPreviousTab(_:)): self = .previousTab
        case #selector(MainWindowViewController.menuBack(_:)): self = .back
        case #selector(MainWindowViewController.menuForward(_:)): self = .forward
        case #selector(MainWindowViewController.menuParent(_:)): self = .parent
        case #selector(MainWindowViewController.menuGoToFolder(_:)): self = .goToFolder
        case #selector(MainWindowViewController.menuSearchDescendants(_:)): self = .searchDescendants
        case #selector(MainWindowViewController.menuHome(_:)): self = .home
        case #selector(MainWindowViewController.menuDownloads(_:)): self = .downloads
        case #selector(MainWindowViewController.menuApplications(_:)): self = .applications
        case #selector(MainWindowViewController.menuSwitchPane(_:)): self = .switchPane
        case #selector(MainWindowViewController.menuSwapPanes(_:)): self = .swapPanes
        case #selector(MainWindowViewController.menuSyncOppositePane(_:)): self = .syncOppositePane
        case #selector(MainWindowViewController.menuRevealInOppositePane(_:)): self = .revealInOppositePane
        case #selector(MainWindowViewController.menuFollowSymbolicLink(_:)): self = .followSymbolicLink
        case #selector(MainWindowViewController.menuCancelOperation(_:)): self = .cancelOperation
        case #selector(MainWindowViewController.menuShowDebugLogs(_:)): self = .debugLogs
        case #selector(MainWindowViewController.menuExportDiagnostics(_:)): self = .exportDiagnostics
        default: return nil
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("PulseFilesToolbarBack")
    static let forward = NSToolbarItem.Identifier("PulseFilesToolbarForward")
    static let search = NSToolbarItem.Identifier("PulseFilesToolbarSearch")
    static let toggleTerminal = NSToolbarItem.Identifier("PulseFilesToolbarTerminal")
    static let toggleSidebar = NSToolbarItem.Identifier("PulseFilesToolbarSidebar")
    static let viewOptions = NSToolbarItem.Identifier("PulseFilesToolbarViewOptions")
    static let settings = NSToolbarItem.Identifier("PulseFilesToolbarSettings")
}

private final class MinimalDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 7 }

    override func drawDivider(in rect: NSRect) {
        NSColor.clear.setFill()
        rect.fill()
        let lineWidth = 1 / max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        let lineRect = NSRect(
            x: rect.midX - lineWidth / 2,
            y: rect.minY + 8,
            width: lineWidth,
            height: max(0, rect.height - 16)
        )
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }
}


extension MainWindowViewController: FilePaneNavigationDelegate {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePaneNavigationEvent) {
        switch event {
        case .activate: activePaneID = pane.paneID
        case .switchPane: performCommand(.switchPane, from: pane.paneID, entrySurface: .paneCallback)
        case let .open(url): performRoutedPaneCallback(.open, from: pane.paneID) { [weak self] in self?.openFile(url, with: nil) }
        case let .directoryChanged(url):
            if pane.paneID == .left { settings.lastLeftDirectory = url } else { settings.lastRightDirectory = url }
            recentLocations.record(url)
            if activePaneID == pane.paneID { terminal.suggestedWorkingDirectory = url }
        case let .directoryAccessGranted(url):
            if pane.paneID == .left { settings.startupLeftDirectory = url } else { settings.startupRightDirectory = url }
        }
    }
}

extension MainWindowViewController: FilePaneCommandDelegate {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePaneCommandEvent) {
        switch event {
        case let .command(command): performCommand(command, from: pane.paneID, entrySurface: .contextMenu)
        case .toggleTerminal: performCommand(.toggleTerminal, from: pane.paneID, entrySurface: .paneCallback)
        case .newFolder: performCommand(.newFolder, from: pane.paneID, entrySurface: .paneCallback)
        case .newFile: performCommand(.newFile, from: pane.paneID, entrySurface: .paneCallback)
        case let .openWith(url, application): performRoutedPaneCallback(.openWith, from: pane.paneID) { [weak self] in self?.openFile(url, with: application) }
        case let .drop(urls, destination, copy): activePaneID = pane.paneID; transferDroppedItems(urls, to: destination, copy: copy)
        case let .rename(item, name): performRoutedPaneCallback(.rename, from: pane.paneID) { [weak self] in self?.rename(item: item, to: name) }
        }
    }
}

extension MainWindowViewController: FilePanePresentationDelegate {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePanePresentationEvent) {
        switch event {
        case let .displayPreferences(hidden, sort): settings.showHiddenFilesByDefault = hidden; settings.setSortDescriptor(sort, for: pane.paneID)
        case let .selection(items): if pane.paneID == activePaneID { sidebar.showSelection(items) }; refreshCommandAvailability()
        case let .searchQuery(query): if pane.paneID == activePaneID { toolbarSearchField?.stringValue = query }
        case let .tabs(state): settings.setPaneTabRestoration(PaneRestorationState(paneState: state), for: pane.paneID); refreshCommandAvailability()
        case let .mode(mode): settings.setPresentationMode(mode, for: pane.paneID)
        }
    }
}

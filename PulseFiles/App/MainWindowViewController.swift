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

final class MainWindowViewController: NSViewController {
    private enum SidebarMetrics {
        static let minWidth: CGFloat = 220
        static let maxWidth: CGFloat = 340
        static let contentMinWidth: CGFloat = 620
    }

    private let settings = SettingsService()
    private let accessPolicy = SandboxFileAccessPolicy.current
    private lazy var fileSystem = FileSystemService(accessPolicy: accessPolicy)
    private lazy var fileOperations = FileOperationService(accessPolicy: accessPolicy)
    private lazy var volumeChangeMonitor = VolumeChangeMonitor()
    private let recentLocations = RecentLocationService()

    private lazy var leftPane = FilePaneViewController(
        paneID: .left,
        viewModel: FilePaneViewModel(
            initialDirectory: accessPolicy.validatedDirectory(settings.launchLeftDirectory),
            showsHiddenFiles: settings.showHiddenFilesByDefault,
            sort: settings.defaultSortDescriptor,
            fileSystem: fileSystem,
            accessPolicy: accessPolicy
        )
    )
    private lazy var rightPane = FilePaneViewController(
        paneID: .right,
        viewModel: FilePaneViewModel(
            initialDirectory: accessPolicy.validatedDirectory(settings.launchRightDirectory),
            showsHiddenFiles: settings.showHiddenFilesByDefault,
            sort: settings.defaultSortDescriptor,
            fileSystem: fileSystem,
            accessPolicy: accessPolicy
        )
    )
    private lazy var sidebar = SidebarViewController(recentLocations: recentLocations, accessPolicy: accessPolicy)
    private let terminal = TerminalViewController()
    private let terminalService = TerminalService()
    private let commandBar = CommandBarView()
    private lazy var fileOperationProgressWindowController = FileOperationProgressWindowController { [weak self] in
        self?.cancelActiveFileOperation()
    }
    private let fileClipboard = FileClipboard()

    private let rootSplitView = NSSplitView()
    private let contentSplitView = NSSplitView()
    private let paneSplitView = MinimalDividerSplitView()
    private let mainStack = NSView()
    private weak var toolbarSearchField: NSSearchField?
    private weak var sidebarToolbarItem: NSToolbarItem?
    private var activeFilterText = ""
    private var settingsWindowController: NSWindowController?
    private var debugLogWindowController: NSWindowController?
    private var didSetInitialSplitPositions = false
    private var keyEventMonitor: Any?
    private var flagsChangedEventMonitor: Any?
    private var sidebarMinWidthConstraint: NSLayoutConstraint?
    private var sidebarMaxWidthConstraint: NSLayoutConstraint?
    private var isSidebarInstalled = false
    private var isTerminalInstalled = false
    private var terminalHeightConstraint: NSLayoutConstraint?
    private var isSinglePaneMode = false
    private var activeOperationTask: Task<Void, Never>?
    private var undoRecovery: FileOperationRecovery?
    private var quickLookPreviewURL: NSURL?
    private var isFileOperationActive = false {
        didSet { setConflictingFileActionsEnabled(!isFileOperationActive) }
    }
    private var clipboardFeedbackTimer: Timer?
    private var clipboardChangeMonitor: Timer?
    private var trackedClipboardChangeCount: Int?

    private var activePaneID: PaneID = .left {
        didSet {
            guard oldValue != activePaneID else { return }
            updateActivePane()
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = LiquidGlassStyle.windowBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        ExperimentalFlags.ensureAppSandboxRootExists()
        #endif
        buildLayout()
        bindPaneCallbacks()
        volumeChangeMonitor.onVolumesChanged = { [weak self] _ in
            guard let self else { return }
            self.sidebar.refreshDevices()
            self.leftPane.refreshAfterVolumeChange()
            self.rightPane.refreshAfterVolumeChange()
        }
        updateActivePane()
        leftPane.loadDirectory()
        rightPane.loadDirectory()
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
        clipboardFeedbackTimer?.invalidate()
        clipboardChangeMonitor?.invalidate()
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

    private func bindPaneCallbacks() {
        terminal.workingDirectoryProvider = { [weak self] in
            guard let self else { return ExperimentalFlags.appSandboxRoot }
            return self.terminalService.resolvedWorkingDirectory(
                activePaneURL: self.targetPane().currentDirectory,
                accessPolicy: self.accessPolicy
            )
        }
        terminal.isShellInteractionAllowedProvider = { [weak self] in
            guard let self else { return false }
            return self.settings.experimentalTerminalEnabled && self.settings.hasAcknowledgedTerminalWarning
        }
        leftPane.onActivate = { [weak self] in self?.activePaneID = .left }
        rightPane.onActivate = { [weak self] in self?.activePaneID = .right }
        leftPane.onSwitchPane = { [weak self] in self?.activePaneID = .right }
        rightPane.onSwitchPane = { [weak self] in self?.activePaneID = .left }
        leftPane.onToggleTerminal = { [weak self] in self?.toggleTerminal() }
        rightPane.onToggleTerminal = { [weak self] in self?.toggleTerminal() }
        leftPane.onNewFolder = { [weak self] in self?.promptForNewFolder() }
        rightPane.onNewFolder = { [weak self] in self?.promptForNewFolder() }
        leftPane.onNewFile = { [weak self] in self?.promptForNewFile() }
        rightPane.onNewFile = { [weak self] in self?.promptForNewFile() }
        leftPane.onOpenURL = { [weak self] fileURL in
            self?.activePaneID = .left
            self?.openFile(fileURL, with: nil)
        }
        rightPane.onOpenURL = { [weak self] fileURL in
            self?.activePaneID = .right
            self?.openFile(fileURL, with: nil)
        }
        leftPane.onOpenWithApplication = { [weak self] fileURL, applicationURL in
            self?.activePaneID = .left
            self?.openFile(fileURL, with: applicationURL)
        }
        rightPane.onOpenWithApplication = { [weak self] fileURL, applicationURL in
            self?.activePaneID = .right
            self?.openFile(fileURL, with: applicationURL)
        }
        leftPane.onCommand = { [weak self] command in
            self?.activePaneID = .left
            self?.performCommand(command)
        }
        rightPane.onCommand = { [weak self] command in
            self?.activePaneID = .right
            self?.performCommand(command)
        }
        leftPane.onDropURLs = { [weak self] urls, destination, shouldCopy in
            self?.activePaneID = .left
            self?.transferDroppedItems(urls, to: destination, copy: shouldCopy)
        }
        rightPane.onDropURLs = { [weak self] urls, destination, shouldCopy in
            self?.activePaneID = .right
            self?.transferDroppedItems(urls, to: destination, copy: shouldCopy)
        }
        leftPane.onDirectoryChanged = { [weak self] url in
            self?.settings.lastLeftDirectory = url
            self?.recentLocations.record(url)
            if self?.activePaneID == .left {
                self?.terminal.suggestedWorkingDirectory = url
            }
        }
        rightPane.onDirectoryChanged = { [weak self] url in
            self?.settings.lastRightDirectory = url
            self?.recentLocations.record(url)
            if self?.activePaneID == .right {
                self?.terminal.suggestedWorkingDirectory = url
            }
        }
        [leftPane, rightPane].forEach { pane in
            pane.onDisplayPreferencesChanged = { [weak self] showsHiddenFiles, sort in
                self?.settings.showHiddenFilesByDefault = showsHiddenFiles
                self?.settings.defaultSortDescriptor = sort
            }
            pane.onSelectionChanged = { [weak self, weak pane] items in
                guard let self, pane?.paneID == self.activePaneID else { return }
                self.sidebar.showSelection(items)
            }
        }
        sidebar.onOpenLocation = { [weak self] url, useInactive in
            self?.targetPane(useInactive: useInactive).navigate(to: url)
        }
        commandBar.onAction = { [weak self] action in
            self?.performCommand(MainCommand(commandBarAction: action))
        }
    }

    private func targetPane(useInactive: Bool = false) -> FilePaneViewController {
        let paneID = useInactive ? activePaneID.opposite : activePaneID
        return paneID == .left ? leftPane : rightPane
    }

    private func updateActivePane() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Active pane switched: pane=\(String(describing: activePaneID)); directory=\(DiagnosticLogger.sanitizedPath(targetPane().currentDirectory))")
        leftPane.setActive(activePaneID == .left)
        rightPane.setActive(activePaneID == .right)
        terminal.suggestedWorkingDirectory = targetPane().currentDirectory
        leftPane.setSearchQuery(activePaneID == .left ? activeFilterText : "")
        rightPane.setSearchQuery(activePaneID == .right ? activeFilterText : "")
        sidebar.showSelection(targetPane().selectedItems)
        targetPane().focusDefaultRowForActivation()
        if view.window?.firstResponder !== toolbarSearchField {
            view.window?.makeFirstResponder(targetPane().tableView)
        }
    }

    private func performCommand(_ command: MainCommand) {
        DiagnosticLogger.log(.info, category: "MainWindow", "Command execution requested: command=\(command); activePane=\(String(describing: activePaneID))")
        guard !isFileOperationActive || !command.conflictsWithFileOperation else {
            DiagnosticLogger.log(.warning, category: "MainWindow", "Command rejected during active file operation: command=\(command)")
            showError(message: "Operation in Progress".localized, detail: "Wait for the current file operation to finish before starting another file-changing action.".localized)
            return
        }

        switch command {
        case .open:
            targetPane().openFocusedItem()
        case .openWith:
            presentOpenWithApplicationPicker()
        case .quickLook:
            showQuickLookForFocusedItem()
        case .newFile:
            promptForNewFile()
        case .newFolder:
            promptForNewFolder()
        case .rename:
            promptForRename()
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
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        case .toggleHiddenFiles:
            targetPane().toggleHiddenFiles()
        case .sortByName:
            targetPane().setSort(.name)
        case .sortByKind:
            targetPane().setSort(.kind)
        case .sortBySize:
            targetPane().setSort(.size)
        case .sortByModified:
            targetPane().setSort(.modified)
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
        case .back:
            targetPane().goBack()
        case .forward:
            targetPane().goForward()
        case .parent:
            targetPane().goParent()
        case .goToFolder:
            promptForGoToFolder()
        case .home, .downloads, .applications:
            targetPane().navigate(to: MainCommandDestinationResolver.destination(for: command))
        case .switchPane:
            activePaneID = activePaneID.opposite
            if isSinglePaneMode {
                rebuildPaneArrangement()
                updateActivePane()
            }
        case .focusLeftPane:
            activePaneID = .left
            if isSinglePaneMode {
                rebuildPaneArrangement()
                updateActivePane()
            }
        case .focusRightPane:
            activePaneID = .right
            if isSinglePaneMode {
                rebuildPaneArrangement()
                updateActivePane()
            }
        case .cancelOperation:
            cancelActiveFileOperation()
        case .debugLogs:
            presentDebugLogs(nil)
        }
    }

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
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        let control = event.modifierFlags.contains(.control)
        if event.keyCode == 53 {
            if isFileOperationActive {
                cancelActiveFileOperation()
            } else {
                view.window?.makeFirstResponder(targetPane().tableView)
            }
            return true
        }
        if let routedCommand = MainCommandRouter().commandForKeyDown(
            keyCode: event.keyCode,
            command: command,
            shift: shift,
            option: option,
            control: control,
            isTextInputFocused: isTextInputFirstResponder
        ) {
            performCommand(routedCommand)
            return true
        }
        if event.isFunctionKey {
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

        do {
            try accessPolicy.validateAccess(to: item.url)
        } catch {
            showError(message: "Preview Blocked".localized, detail: error.localizedDescription)
            return
        }

        guard FileManager.default.fileExists(atPath: item.url.path) else {
            showError(message: "Preview Unavailable".localized, detail: "The selected item no longer exists.".localized)
            return
        }

        quickLookPreviewURL = item.url as NSURL
        guard let panel = QLPreviewPanel.shared() else {
            showError(message: "Preview Unavailable".localized, detail: "Quick Look is not available for this item.".localized)
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

extension MainWindowViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookPreviewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookPreviewURL
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension MainWindowViewController: NSToolbarDelegate, NSToolbarItemValidation {
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
            item.searchField.placeholderString = "Filter active pane".localized
            item.searchField.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.searchField)
            item.searchField.target = self
            item.searchField.action = #selector(toolbarSearchChanged(_:))
            item.searchField.sendsSearchStringImmediately = true
            toolbarSearchField = item.searchField
            return item
        case .toggleTerminal:
            let item = toolbarItem(itemIdentifier, label: "Terminal".localized, symbol: "terminal", action: #selector(toolbarToggleTerminal(_:)))
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
        performCommand(.back)
    }

    @objc private func toolbarForward(_ sender: Any?) {
        performCommand(.forward)
    }

    @objc private func toolbarToggleTerminal(_ sender: Any?) {
        performCommand(.toggleTerminal)
    }

    @objc private func toolbarToggleSidebar(_ sender: Any?) {
        performCommand(.toggleSidebar)
    }

    @objc func toolbarSettings(_ sender: Any?) {
        presentSettings(sender)
    }

    func reloadSettingsFromJSONIfChanged() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Settings reload requested from JSON")
        settings.importJSONIfChanged()
        applySettingsChanges()
        (settingsWindowController?.contentViewController as? SettingsViewController)?.reloadFromSettings()
    }

    private func presentSettings(_ sender: Any?) {
        reloadSettingsFromJSONIfChanged()
        if let existingWindow = settingsWindowController?.window, existingWindow.isVisible {
            sizeAndPositionSettingsWindow(existingWindow, preferredContentSize: existingWindow.contentViewController?.preferredContentSize ?? NSSize(width: 680, height: 500))
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let controller = SettingsViewController(settings: settings)
        controller.onChange = { [weak self] in self?.applySettingsChanges() }
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings".localized
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 420)
        window.maxSize = NSSize(width: 760, height: 560)
        sizeAndPositionSettingsWindow(window, preferredContentSize: controller.preferredContentSize)
        window.delegate = self

        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func sizeAndPositionSettingsWindow(_ window: NSWindow, preferredContentSize: NSSize) {
        let screen = view.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let maxContentWidth = max(600, visibleFrame.width - 100)
        let maxContentHeight = max(420, visibleFrame.height - 120)
        let contentSize = NSSize(
            width: min(max(preferredContentSize.width, 600), min(760, maxContentWidth)),
            height: min(max(preferredContentSize.height, 420), min(540, maxContentHeight))
        )

        window.setContentSize(contentSize)
        let frameSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - frameSize.width / 2,
            y: visibleFrame.midY - frameSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true)
    }

    private func presentDebugLogs(_ sender: Any?) {
        if let existingWindow = debugLogWindowController?.window, existingWindow.isVisible {
            sizeAndPositionDebugLogWindow(existingWindow, preferredContentSize: existingWindow.contentViewController?.preferredContentSize ?? NSSize(width: 900, height: 520))
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let controller = DebugLogViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Debug Logs".localized
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 360)
        sizeAndPositionDebugLogWindow(window, preferredContentSize: controller.preferredContentSize)
        window.delegate = self

        let windowController = NSWindowController(window: window)
        debugLogWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func sizeAndPositionDebugLogWindow(_ window: NSWindow, preferredContentSize: NSSize) {
        let screen = view.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 760)
        let contentSize = NSSize(
            width: min(max(preferredContentSize.width, 720), max(720, visibleFrame.width - 120)),
            height: min(max(preferredContentSize.height, 360), max(360, visibleFrame.height - 120))
        )
        window.setContentSize(contentSize)
        let frameSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - frameSize.width / 2,
            y: visibleFrame.midY - frameSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true)
    }

    private func applySettingsChanges() {
        DiagnosticLogger.log(.info, category: "MainWindow", "Applying settings changes: terminalEnabled=\(settings.experimentalTerminalEnabled); terminalDefaultVisible=\(settings.defaultTerminalVisible); sidebarDefaultVisible=\(settings.defaultSidebarVisible); singlePane=\(settings.defaultSinglePaneMode)")
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        view.layer?.backgroundColor = LiquidGlassStyle.windowBackground.cgColor
        view.window?.backgroundColor = LiquidGlassStyle.windowBackground
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
        leftPane.setSort(settings.defaultSortDescriptor.key, ascending: settings.defaultSortDescriptor.ascending)
        rightPane.setSort(settings.defaultSortDescriptor.key, ascending: settings.defaultSortDescriptor.ascending)
        #if DEBUG
        ExperimentalFlags.ensureAppSandboxRootExists()
        #endif
        if accessPolicy.isEnabled {
            if !accessPolicy.canAccess(leftPane.currentDirectory) {
                leftPane.navigate(to: accessPolicy.validatedDirectory(leftPane.currentDirectory))
            }
            if !accessPolicy.canAccess(rightPane.currentDirectory) {
                rightPane.navigate(to: accessPolicy.validatedDirectory(rightPane.currentDirectory))
            }
        }
        sidebar.refresh()
        commandBar.refreshAppearance()
        terminal.refreshAppearance()
        view.layoutSubtreeIfNeeded()
        applySidebarSplitPosition()
        leftPane.refreshAppearance()
        rightPane.refreshAppearance()
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
        menu.addItem(menuItem("Sort by Kind".localized, action: #selector(menuSortByKind(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Size".localized, action: #selector(menuSortBySize(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Modified".localized, action: #selector(menuSortByModified(_:)), key: "", modifiers: []))
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
        activeFilterText = sender.stringValue
        targetPane().setSearchQuery(activeFilterText)
    }

    private func setSinglePaneMode(_ singlePane: Bool, focusPane: PaneID) {
        isSinglePaneMode = singlePane
        activePaneID = focusPane
        rebuildPaneArrangement()
        updateActivePane()
    }

    private func rebuildPaneArrangement() {
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
        if isTerminalInstalled {
            removeTerminalPanel()
            settings.isTerminalVisible = false
            view.window?.makeFirstResponder(targetPane().tableView)
        } else {
            guard settings.experimentalTerminalEnabled else {
                DiagnosticLogger.log(.warning, category: "Terminal", "Terminal toggle denied because experimental terminal is disabled")
                showTerminalDisabledAlert()
                return
            }
            installTerminalPanel(showWarning: true)
            settings.isTerminalVisible = true
            terminal.suggestedWorkingDirectory = terminalService.resolvedWorkingDirectory(
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
        contentSplitView.addArrangedSubview(terminal.view)
        if terminalHeightConstraint == nil {
            terminalHeightConstraint = terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        }
        terminalHeightConstraint?.isActive = true
        isTerminalInstalled = true
    }

    private func showTerminalDisabledAlert() {
        let alert = NSAlert()
        alert.messageText = "Experimental terminal is disabled".localized
        alert.informativeText = "Enable the experimental terminal in Settings before opening it. Shell commands can modify or delete files.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showFirstUseTerminalWarningIfNeeded() {
        let warningState = terminalService.warningState(settings: settings, accessPolicy: accessPolicy)
        guard !warningState.isAcknowledged else { return }

        let alert = NSAlert()
        alert.messageText = warningState.messageText
        alert.informativeText = warningState.informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I Understand".localized)
        let acknowledgementResponse = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let terminalService = terminalService
        let settings = settings
        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                guard terminalService.shouldAcknowledgeFirstUseWarning(
                    response: response.rawValue,
                    acknowledgementResponse: acknowledgementResponse
                ) else { return }
                terminalService.acknowledgeFirstUseWarning(settings: settings)
            }
        } else {
            let response = alert.runModal()
            if terminalService.shouldAcknowledgeFirstUseWarning(
                response: response.rawValue,
                acknowledgementResponse: acknowledgementResponse
            ) {
                terminalService.acknowledgeFirstUseWarning(settings: settings)
            }
        }
    }

    private func removeTerminalPanel() {
        guard isTerminalInstalled else { return }
        DiagnosticLogger.log(.info, category: "Terminal", "Removing terminal panel")
        terminal.stopRunningCommand()
        terminalHeightConstraint?.isActive = false
        contentSplitView.removeArrangedSubview(terminal.view)
        terminal.view.removeFromSuperview()
        isTerminalInstalled = false
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
        let width = clampedSidebarWidth(CGFloat(settings.sidebarWidth))
        rootSplitView.setPosition(max(SidebarMetrics.contentMinWidth, rootSplitView.bounds.width - width), ofDividerAt: 0)
    }

    private func installSidebarView() {
        guard !isSidebarInstalled else { return }
        sidebar.view.isHidden = false
        sidebarMinWidthConstraint?.isActive = true
        sidebarMaxWidthConstraint?.isActive = true
        rootSplitView.addArrangedSubview(sidebar.view)
        isSidebarInstalled = true
    }

    private func removeSidebarView() {
        guard isSidebarInstalled else { return }
        sidebarMinWidthConstraint?.isActive = false
        sidebarMaxWidthConstraint?.isActive = false
        rootSplitView.removeArrangedSubview(sidebar.view)
        sidebar.view.removeFromSuperview()
        sidebar.view.isHidden = true
        isSidebarInstalled = false
    }

    private func persistSidebarWidthFromSplitPosition() {
        guard isSidebarInstalled, rootSplitView.arrangedSubviews.count > 1, rootSplitView.bounds.width > 0 else { return }
        settings.sidebarWidth = Double(clampedSidebarWidth(sidebar.view.frame.width))
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, SidebarMetrics.minWidth), SidebarMetrics.maxWidth)
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
        let alert = NSAlert()
        alert.messageText = "New Folder".localized
        alert.informativeText = "Create a folder in %@".localized(with: targetPane().currentDirectory.path)
        alert.addButton(withTitle: "Create".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let textField = NSTextField(string: uniqueFolderName(in: targetPane().currentDirectory))
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.createFolder(named: textField.stringValue)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func promptForNewFile() {
        view.window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "New File".localized
        alert.informativeText = "Create a file in %@".localized(with: targetPane().currentDirectory.path)
        alert.addButton(withTitle: "Create".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let textField = NSTextField(string: uniqueFileName(in: targetPane().currentDirectory))
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.createFile(named: textField.stringValue)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func uniqueFolderName(in directory: URL) -> String {
        let fileManager = FileManager.default
        let base = "Untitled Folder"
        var candidate = base
        var index = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(base) \(index)"
            index += 1
        }
        return candidate
    }

    private func uniqueFileName(in directory: URL) -> String {
        let fileManager = FileManager.default
        let base = "Untitled.txt"
        var candidate = base
        var index = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "Untitled \(index).txt"
            index += 1
        }
        return candidate
    }

    private func createFolder(named rawName: String) {
        do {
            let destination = try fileOperations.createFolder(named: rawName, in: targetPane().currentDirectory)
            targetPane().loadDirectory(selecting: destination)
        } catch let error as FileNameValidator.ValidationError {
            showError(message: "Invalid Folder Name".localized, detail: error.localizedDescription)
        } catch {
            showError(message: "Could Not Create Folder".localized, detail: error.localizedDescription)
        }
    }

    private func createFile(named rawName: String) {
        do {
            let destination = try fileOperations.createFile(named: rawName, in: targetPane().currentDirectory)
            targetPane().loadDirectory(selecting: destination)
        } catch let error as FileNameValidator.ValidationError {
            showError(message: "Invalid File Name".localized, detail: error.localizedDescription)
        } catch {
            showError(message: "Could Not Create File".localized, detail: error.localizedDescription)
        }
    }

    private func presentOpenWithApplicationPicker() {
        let selectedFiles = targetPane().selectedItems.filter { !$0.isDirectory }
        guard !selectedFiles.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more files to open with another application.".localized)
            return
        }

        do {
            for item in selectedFiles {
                try accessPolicy.validateAccess(to: item.url)
                guard FileManager.default.fileExists(atPath: item.url.path) else {
                    throw FileOperationError.sourceMissing(item.url)
                }
            }
        } catch {
            showError(message: "Could Not Open File".localized, detail: error.localizedDescription)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open With…".localized
        panel.prompt = "Open".localized
        panel.message = selectedFiles.count == 1
            ? "Choose an application to open %@.".localized(with: selectedFiles[0].url.lastPathComponent)
            : "Choose an application to open the selected files.".localized
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let applicationURL = panel?.url else { return }
            selectedFiles.forEach { self?.openFile($0.url, with: applicationURL) }
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openFile(_ fileURL: URL, with applicationURL: URL?) {
        do {
            try accessPolicy.validateAccess(to: fileURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw FileOperationError.sourceMissing(fileURL)
            }

            if let applicationURL {
                guard FileManager.default.fileExists(atPath: applicationURL.path) else {
                    throw FileOperationError.sourceMissing(applicationURL)
                }
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
                    if let error {
                        self?.showError(message: "Could Not Open File".localized, detail: error.localizedDescription)
                    }
                }
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        } catch {
            showError(message: "Could Not Open File".localized, detail: error.localizedDescription)
        }
    }

    private func promptForGoToFolder() {
        view.window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "Go to Folder".localized
#if DEBUG
        alert.informativeText = ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? "Enter a folder path inside the PulseFiles experimental sandbox.".localized
            : "Enter an absolute, home-relative, or active-pane-relative folder path. If macOS denies access, open or grant the folder first.".localized
#else
        alert.informativeText = "Enter an absolute, home-relative, or active-pane-relative folder path. If macOS denies access, open or grant the folder first.".localized
#endif
        alert.addButton(withTitle: "Go".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let textField = NSTextField(string: targetPane().currentDirectory.path)
        textField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = textField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.goToFolder(path: textField.stringValue)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func goToFolder(path rawPath: String) {
        do {
            let url = try resolveFolderPath(rawPath)
            targetPane().navigate(to: url)
        } catch {
            showError(message: "Could Not Go to Folder".localized, detail: error.localizedDescription)
        }
    }

    private func resolveFolderPath(_ rawPath: String) throws -> URL {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { throw FileNameValidator.ValidationError.empty }

        let expandedPath: String
        if trimmedPath == "~" {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmedPath.hasPrefix("~/") {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmedPath.dropFirst(2)))
                .path
        } else if trimmedPath.hasPrefix("/") {
            expandedPath = trimmedPath
        } else {
            expandedPath = targetPane().currentDirectory.appendingPathComponent(trimmedPath).path
        }

        let url = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        try accessPolicy.validateAccess(to: url)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileOperationError.destinationDirectoryMissing(url)
        }
        guard isDirectory.boolValue else {
            throw FileOperationError.destinationNotDirectory(url)
        }
        return url
    }

    private func promptForRename() {
        guard let item = targetPane().focusedItem else {
            showError(message: "Nothing Selected".localized, detail: "Select one item to rename.".localized)
            return
        }

        view.window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "Rename".localized
        alert.informativeText = item.url.path
        alert.addButton(withTitle: "Rename".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let textField = NSTextField(string: item.filename)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.rename(item: item, to: textField.stringValue)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func rename(item: FileItem, to rawName: String) {
        startFileOperation(named: "Rename".localized, captureRecovery: true) { [fileOperations] progressHandler in
            try await fileOperations.rename(item.url, to: rawName, progressHandler: progressHandler)
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
        startFileOperation(named: operationName) { [fileOperations] progressHandler in
            if permanently {
                return try await fileOperations.delete(items.map(\.url), progressHandler: progressHandler)
            }
            return try await fileOperations.trash(items.map(\.url), progressHandler: progressHandler)
        }
    }

    private func copySelectedItems() {
        performFileTransfer(kind: "Copy".localized, shouldConfirm: settings.confirmCopyOperations) { [fileOperations] request, conflictHandler, progressHandler in
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
        guard FilePathComparison.firstDirectoryContaining(destinationDirectory, among: sources) == nil else {
            showError(
                message: "Cannot Complete \(kind)".localized,
                detail: "Cannot copy or move an item into itself or one of its subfolders.".localized
            )
            return
        }

        let request = FileOperationRequest(sources: sources, destinationDirectory: destinationDirectory)
        let start: () -> Void = { [weak self] in
            self?.startFileOperation(named: kind, captureRecovery: captureRecovery) { [weak self] progressHandler in
                try await operation(request, { destination in
                    guard let self else { return .cancel }
                    return await self.promptForConflict(destination: destination, operationName: kind)
                }, progressHandler)
            }
        }

        if shouldConfirm {
            confirmFileOperation(kind, urls: sources, destinationDirectory: destinationDirectory, confirmButtonTitle: kind, completion: start)
        } else {
            start()
        }
    }


    private func writeSelectionToClipboard(operation: FileClipboard.Operation) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected".localized, detail: "Select one or more items in the active pane.".localized)
            return
        }
        do {
            for url in sources {
                try accessPolicy.validateAccess(to: url)
            }
            fileClipboard.write(urls: sources, operation: operation)
            showClipboardFeedback(for: operation, itemCount: sources.count)
            updateCutItemMarkers(operation: operation, urls: sources, sourcePane: targetPane())
            beginClipboardChangeMonitoring()
        } catch {
            showError(message: "Could Not Use Clipboard".localized, detail: error.localizedDescription)
        }
    }

    private func pasteClipboardItems() {
        guard let payload = fileClipboard.read(), !payload.urls.isEmpty else {
            clearClipboardFeedback()
            showError(message: "Clipboard Is Empty".localized, detail: "Copy or cut one or more files before pasting.".localized)
            return
        }
        let kind = payload.operation == .copy ? "Paste Copy".localized : "Paste Move".localized
        let shouldConfirm = payload.operation == .copy ? settings.confirmCopyOperations : settings.confirmMoveOperations
        performFileTransfer(
            kind: kind,
            sources: payload.urls,
            destinationDirectory: targetPane().currentDirectory,
            shouldConfirm: shouldConfirm,
            captureRecovery: payload.operation == .move
        ) { [fileOperations] request, conflictHandler, progressHandler in
            switch payload.operation {
            case .copy:
                return try await fileOperations.copy(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
            case .move:
                return try await fileOperations.move(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
            }
        }
    }

    private func showClipboardFeedback(for operation: FileClipboard.Operation, itemCount: Int) {
        let verb = operation == .copy ? "Copied".localized : "Cut".localized
        let itemLabel = itemCount == 1 ? "item".localized : "items".localized
        commandBar.setTransientStatus("%@ %d %@".localized(with: verb, itemCount, itemLabel))
        clipboardFeedbackTimer?.invalidate()
        clipboardFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.commandBar.clearOperationStatus()
            self?.clipboardFeedbackTimer = nil
        }
    }

    private func updateCutItemMarkers(operation: FileClipboard.Operation, urls: [URL], sourcePane: FilePaneViewController) {
        leftPane.setDimmedFileURLs([])
        rightPane.setDimmedFileURLs([])
        guard operation == .move else { return }
        sourcePane.setDimmedFileURLs(urls)
    }

    private func beginClipboardChangeMonitoring() {
        trackedClipboardChangeCount = fileClipboard.changeCount
        clipboardChangeMonitor?.invalidate()
        clipboardChangeMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let trackedClipboardChangeCount = self.trackedClipboardChangeCount else { return }
            if self.fileClipboard.changeCount != trackedClipboardChangeCount {
                self.clearClipboardFeedback()
            }
        }
    }

    private func clearClipboardFeedback() {
        clipboardFeedbackTimer?.invalidate()
        clipboardFeedbackTimer = nil
        clipboardChangeMonitor?.invalidate()
        clipboardChangeMonitor = nil
        trackedClipboardChangeCount = nil
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
        do {
            try validateDroppedItems(urls, destinationDirectory: destinationDirectory)
        } catch {
            showError(message: "Could Not Accept Drop".localized, detail: error.localizedDescription)
            return
        }

        let kind = copy ? "Copy".localized : "Move".localized
        let request = FileOperationRequest(sources: urls, destinationDirectory: destinationDirectory)
        let start: () -> Void = { [weak self, fileOperations] in
            self?.startFileOperation(named: kind, captureRecovery: !copy) { [weak self] progressHandler in
                if copy {
                    return try await fileOperations.copy(request, conflictHandler: { destination in
                        guard let self else { return .cancel }
                        return await self.promptForConflict(destination: destination, operationName: kind)
                    }, progressHandler: progressHandler)
                }
                return try await fileOperations.move(request, conflictHandler: { destination in
                    guard let self else { return .cancel }
                    return await self.promptForConflict(destination: destination, operationName: kind)
                }, progressHandler: progressHandler)
            }
        }
        let shouldConfirm = copy ? settings.confirmCopyOperations : settings.confirmMoveOperations
        if shouldConfirm {
            confirmFileOperation(kind, urls: urls, destinationDirectory: destinationDirectory, confirmButtonTitle: kind, completion: start)
        } else {
            start()
        }
    }

    private func validateDroppedItems(_ urls: [URL], destinationDirectory: URL) throws {
        try accessPolicy.validateAccess(to: destinationDirectory)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory) else {
            throw FileOperationError.destinationDirectoryMissing(destinationDirectory)
        }
        guard isDirectory.boolValue else {
            throw FileOperationError.destinationNotDirectory(destinationDirectory)
        }

        for url in urls {
            try accessPolicy.validateAccess(to: url)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw FileOperationError.sourceMissing(url)
            }
        }
    }

    private func confirmFileOperation(
        _ operationName: String,
        urls: [URL],
        destinationDirectory: URL?,
        confirmButtonTitle: String,
        completion: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let itemLabel = urls.count == 1 ? "Item".localized : "%d Items".localized(with: urls.count)
        alert.messageText = "%@ %@?".localized(with: operationName, itemLabel)
        alert.informativeText = confirmationSummary(
            operationName: operationName,
            urls: urls,
            destinationDirectory: destinationDirectory
        )
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel — Do Not Start".localized)

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

    private func confirmationSummary(operationName: String, urls: [URL], destinationDirectory: URL?) -> String {
        let itemLabel = urls.count == 1 ? "1 item".localized : "%d items".localized(with: urls.count)
        var lines = [
            "Operation: %@".localized(with: operationName),
            "%@ %@:".localized(with: operationName, itemLabel)
        ]
        let visibleNames = urls.prefix(8).map { "- \($0.lastPathComponent)" }
        lines.append(contentsOf: visibleNames)
        if urls.count > visibleNames.count {
            lines.append("- ...and %d more".localized(with: urls.count - visibleNames.count))
        }
        let sourceVolumes = Dictionary(grouping: urls, by: { VolumeStatusPresentation.resolve(for: $0).locationDescription }).keys.sorted()
        if !sourceVolumes.isEmpty {
            lines.append("")
            lines.append("Source volume%@: %@".localized(with: sourceVolumes.count == 1 ? "" : "s", sourceVolumes.joined(separator: ", ")))
        }
        if let destinationDirectory {
            lines.append("")
            lines.append("Destination: %@".localized(with: destinationDirectory.path))
            lines.append("Destination volume: %@".localized(with: VolumeStatusPresentation.resolve(for: destinationDirectory).locationDescription))
        }
        return lines.joined(separator: "\n")
    }

    private func undoLastOperation() {
        guard let recovery = undoRecovery else {
            showError(message: "Undo Unavailable".localized, detail: "The last operation cannot be safely undone.".localized)
            return
        }
        undoRecovery = nil
        startFileOperation(named: "Undo".localized) { [fileOperations] progressHandler in
            try await fileOperations.undo(recovery, progressHandler: progressHandler)
        }
    }

    private func cancelActiveFileOperation() {
        guard isFileOperationActive else { return }
        activeOperationTask?.cancel()
        fileOperationProgressWindowController.showCancellationPending()
    }

    private func startFileOperation(named operationName: String, captureRecovery: Bool = false, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult) {
        guard !isFileOperationActive else { return }
        let previousWindowTitle = view.window?.title
        isFileOperationActive = true
        fileOperationProgressWindowController.show(operationName: operationName, parentWindow: view.window)
        activeOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if let previousWindowTitle {
                    self.view.window?.title = previousWindowTitle
                }
                self.fileOperationProgressWindowController.dismiss()
                self.isFileOperationActive = false
                self.activeOperationTask = nil
            }

            do {
                // Keep the operation coordinator and every AppKit update on the
                // main actor, while ensuring a service implementation cannot do
                // synchronous filesystem work on the UI executor before its
                // first suspension point.
                let result = try await runFileOperationOffMain {
                    try await operation { [weak self] progress in
                        self?.updateFileOperationProgress(progress, operationName: operationName)
                    }
                }
                if captureRecovery { self.undoRecovery = result.succeededCompletely ? result.recovery : nil }
                self.clearClipboardFeedback()
                self.refreshBothPanes()
                self.showOperationResult(result, operationName: operationName)
            } catch {
                let localizedError = error as? LocalizedError
                let detail = localizedError?.failureReason ?? error.localizedDescription
                self.showError(message: "Could Not %@ Items".localized(with: operationName), detail: detail)
            }
        }
    }

    private func runFileOperationOffMain(
        _ operation: @escaping @Sendable () async throws -> FileOperationResult
    ) async throws -> FileOperationResult {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String) {
        fileOperationProgressWindowController.update(operationName: operationName, progress: progress)
        view.window?.title = "\(operationName): \(progress.currentItemName)"
    }

    static func operationResultPresentation(_ result: FileOperationResult, operationName: String) -> (message: String, detail: String, style: NSAlert.Style)? {
        guard !result.succeededCompletely else { return nil }
        var details = [
            "Completed: %d".localized(with: result.completedItems.count),
            "Skipped: %d".localized(with: result.skippedItems.count),
            "Failed: %d".localized(with: result.failedItems.count),
            "Cleanup warnings: %d".localized(with: result.cleanupWarnings.count)
        ]
        if result.wasCancelled { details.append("The whole operation was cancelled before all items completed.".localized) }
        if !result.failedItems.isEmpty {
            details.append("Partial failure: some selected items were not changed.".localized)
        }
        details.append(contentsOf: result.failedItems.map { "\($0.url.lastPathComponent): \($0.error.localizedDescription)" })
        details.append(contentsOf: result.cleanupWarnings.map { "\($0.url.lastPathComponent): \($0.message)" })

        let onlyCancelled = result.wasCancelled && result.failedItems.isEmpty && result.cleanupWarnings.isEmpty
        let message = onlyCancelled
            ? "%@ Cancelled".localized(with: operationName)
            : "%@ Finished With Issues".localized(with: operationName)
        return (message, details.joined(separator: "\n"), onlyCancelled ? .informational : .warning)
    }

    private func showOperationResult(_ result: FileOperationResult, operationName: String) {
        guard let presentation = Self.operationResultPresentation(result, operationName: operationName) else { return }
        showAlert(message: presentation.message, detail: presentation.detail, style: presentation.style)
    }

    private func setConflictingFileActionsEnabled(_ isEnabled: Bool) {
        commandBar.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSControl }.forEach { control in
            guard let rawValue = control.identifier?.rawValue, let action = CommandBarAction(rawValue: rawValue) else { return }
            control.isEnabled = !MainCommand(commandBarAction: action).conflictsWithFileOperation || isEnabled
        }
    }

    @MainActor
    private func promptForConflict(destination: URL, operationName: String) async -> FileConflictResolution {
        let keepBothDestination = FileOperationService.keepBothDestination(
            for: destination,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "An Item With This Name Already Exists".localized
        alert.informativeText = "%@ already exists in %@. Keep Both will save the incoming item as %@ during this %@ operation.".localized(
            with: destination.lastPathComponent,
            destination.deletingLastPathComponent().path,
            keepBothDestination.lastPathComponent,
            operationName
        )
        alert.addButton(withTitle: "Keep Both — Use New Name".localized)
        alert.addButton(withTitle: "Replace Existing Item".localized)
        alert.addButton(withTitle: "Skip This Item".localized)
        alert.addButton(withTitle: "Cancel Whole Operation".localized)

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
        leftPane.loadDirectory()
        rightPane.loadDirectory()
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

extension MainWindowViewController: NSSplitViewDelegate {
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

extension MainWindowViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindowController?.window {
            settingsWindowController = nil
            view.window?.makeKeyAndOrderFront(nil)
        } else if window === debugLogWindowController?.window {
            debugLogWindowController = nil
            view.window?.makeKeyAndOrderFront(nil)
        }
    }
}

extension MainWindowViewController: NSMenuItemValidation {
    @objc func menuNewFile(_ sender: Any?) { performCommand(.newFile) }
    @objc func menuNewFolder(_ sender: Any?) { performCommand(.newFolder) }
    @objc func menuRename(_ sender: Any?) { performCommand(.rename) }
    @objc func menuUndo(_ sender: Any?) { performCommand(.undo) }
    @objc func menuOpenWith(_ sender: Any?) { performCommand(.openWith) }
    @objc func menuCopy(_ sender: Any?) { performCommand(.copy) }
    @objc func menuMove(_ sender: Any?) { performCommand(.move) }
    @objc func menuCopyToClipboard(_ sender: Any?) { performCommand(.copyToClipboard) }
    @objc func menuCutToClipboard(_ sender: Any?) { performCommand(.cutToClipboard) }
    @objc func menuPasteFromClipboard(_ sender: Any?) { performCommand(.pasteFromClipboard) }
    @objc func menuMoveToTrash(_ sender: Any?) { performCommand(.trash) }
    @objc func menuRefresh(_ sender: Any?) { performCommand(.refresh) }
    @objc func menuReveal(_ sender: Any?) { performCommand(.reveal) }
    @objc func menuToggleHiddenFiles(_ sender: Any?) { performCommand(.toggleHiddenFiles) }
    @objc func menuSortByName(_ sender: Any?) { performCommand(.sortByName) }
    @objc func menuSortByKind(_ sender: Any?) { performCommand(.sortByKind) }
    @objc func menuSortBySize(_ sender: Any?) { performCommand(.sortBySize) }
    @objc func menuSortByModified(_ sender: Any?) { performCommand(.sortByModified) }
    @objc func menuSortAscending(_ sender: Any?) { performCommand(.sortAscending) }
    @objc func menuSortDescending(_ sender: Any?) { performCommand(.sortDescending) }
    @objc func menuToggleTerminal(_ sender: Any?) { performCommand(.toggleTerminal) }
    @objc func menuToggleSidebar(_ sender: Any?) { performCommand(.toggleSidebar) }
    @objc func menuTogglePaneLayout(_ sender: Any?) { performCommand(.togglePaneLayout) }
    @objc func menuBack(_ sender: Any?) { performCommand(.back) }
    @objc func menuForward(_ sender: Any?) { performCommand(.forward) }
    @objc func menuParent(_ sender: Any?) { performCommand(.parent) }
    @objc func menuGoToFolder(_ sender: Any?) { performCommand(.goToFolder) }
    @objc func menuHome(_ sender: Any?) { performCommand(.home) }
    @objc func menuDownloads(_ sender: Any?) { performCommand(.downloads) }
    @objc func menuApplications(_ sender: Any?) { performCommand(.applications) }
    @objc func menuSwitchPane(_ sender: Any?) { performCommand(.switchPane) }
    @objc func menuFocusLeftPane(_ sender: Any?) { performCommand(.focusLeftPane) }
    @objc func menuFocusRightPane(_ sender: Any?) { performCommand(.focusRightPane) }
    @objc func menuCancelOperation(_ sender: Any?) { performCommand(.cancelOperation) }
    @objc func menuSettings(_ sender: Any?) { presentSettings(sender) }
    @objc func menuShowDebugLogs(_ sender: Any?) { performCommand(.debugLogs) }
    @objc func menuEditSettingsJSON(_ sender: Any?) {
        do {
            let url = try settings.writeSettingsJSON()
            NSWorkspace.shared.open(url)
        } catch {
            showError(message: "Could Not Open Settings JSON".localized, detail: error.localizedDescription)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(menuToggleSidebar(_:)) {
            menuItem.state = isSidebarInstalled ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuToggleTerminal(_:)) {
            menuItem.state = isTerminalInstalled ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuTogglePaneLayout(_:)) {
            menuItem.title = isSinglePaneMode ? "Use Dual Pane".localized : "Use Single Pane".localized
            menuItem.state = isSinglePaneMode ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuToggleHiddenFiles(_:)) {
            menuItem.state = targetPane().showsHiddenFiles ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuMoveToTrash(_:)) {
            menuItem.title = settings.permanentlyDeleteInsteadOfTrash ? "Permanently Delete".localized : "Move to Trash".localized
        }
        let sort = targetPane().sortDescriptor
        if menuItem.action == #selector(menuSortByName(_:)) {
            menuItem.state = sort.key == .name ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuSortByKind(_:)) {
            menuItem.state = sort.key == .kind ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuSortBySize(_:)) {
            menuItem.state = sort.key == .size ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuSortByModified(_:)) {
            menuItem.state = sort.key == .modified ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuSortAscending(_:)) {
            menuItem.state = sort.ascending ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuSortDescending(_:)) {
            menuItem.state = sort.ascending ? .off : .on
            return true
        }
        menuItem.state = .off
        guard let command = MainCommand(menuAction: menuItem.action) else { return true }
        if case .disabled = MainCommandRouter().route(command, in: currentRoutingState()) {
            return false
        }
        return true
    }

    private func currentRoutingState() -> MainCommandRoutingState {
        let leftSelectedURLs = leftPane.selectedItems.map(\.url)
        let rightSelectedURLs = rightPane.selectedItems.map(\.url)
        let leftFocusedURL = leftPane.focusedItem?.url
        let rightFocusedURL = rightPane.focusedItem?.url
        let activeSelectedURLs = activePaneID == .left ? leftSelectedURLs : rightSelectedURLs
        let activeFocusedURL = activePaneID == .left ? leftFocusedURL : rightFocusedURL
        let activeURLs = activeSelectedURLs + [activeFocusedURL].compactMap { $0 }
        let sandboxAllowsSelectedURLs = activeURLs.allSatisfy { accessPolicy.canAccess($0) }

        return MainCommandRoutingState(
            activePaneID: activePaneID,
            leftPane: MainCommandRoutingPane(
                id: .left,
                currentDirectory: leftPane.currentDirectory,
                selectedURLs: leftSelectedURLs,
                focusedURL: leftFocusedURL
            ),
            rightPane: MainCommandRoutingPane(
                id: .right,
                currentDirectory: rightPane.currentDirectory,
                selectedURLs: rightSelectedURLs,
                focusedURL: rightFocusedURL
            ),
            isFileOperationActive: isFileOperationActive,
            sandboxAllowsSelectedURLs: sandboxAllowsSelectedURLs,
            hasUndoRecovery: undoRecovery != nil
        )
    }
}

private extension MainCommand {
    init?(menuAction: Selector?) {
        guard let menuAction else { return nil }
        switch menuAction {
        case #selector(MainWindowViewController.menuNewFile(_:)): self = .newFile
        case #selector(MainWindowViewController.menuNewFolder(_:)): self = .newFolder
        case #selector(MainWindowViewController.menuRename(_:)): self = .rename
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
        case #selector(MainWindowViewController.menuSortByKind(_:)): self = .sortByKind
        case #selector(MainWindowViewController.menuSortBySize(_:)): self = .sortBySize
        case #selector(MainWindowViewController.menuSortByModified(_:)): self = .sortByModified
        case #selector(MainWindowViewController.menuSortAscending(_:)): self = .sortAscending
        case #selector(MainWindowViewController.menuSortDescending(_:)): self = .sortDescending
        case #selector(MainWindowViewController.menuToggleTerminal(_:)): self = .toggleTerminal
        case #selector(MainWindowViewController.menuToggleSidebar(_:)): self = .toggleSidebar
        case #selector(MainWindowViewController.menuTogglePaneLayout(_:)): self = .togglePaneLayout
        case #selector(MainWindowViewController.menuBack(_:)): self = .back
        case #selector(MainWindowViewController.menuForward(_:)): self = .forward
        case #selector(MainWindowViewController.menuParent(_:)): self = .parent
        case #selector(MainWindowViewController.menuGoToFolder(_:)): self = .goToFolder
        case #selector(MainWindowViewController.menuHome(_:)): self = .home
        case #selector(MainWindowViewController.menuDownloads(_:)): self = .downloads
        case #selector(MainWindowViewController.menuApplications(_:)): self = .applications
        case #selector(MainWindowViewController.menuSwitchPane(_:)): self = .switchPane
        case #selector(MainWindowViewController.menuFocusLeftPane(_:)): self = .focusLeftPane
        case #selector(MainWindowViewController.menuFocusRightPane(_:)): self = .focusRightPane
        case #selector(MainWindowViewController.menuCancelOperation(_:)): self = .cancelOperation
        case #selector(MainWindowViewController.menuShowDebugLogs(_:)): self = .debugLogs
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
        LiquidGlassStyle.subtleStroke.setFill()
        lineRect.fill()
    }
}

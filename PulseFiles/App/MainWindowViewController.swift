import AppKit

final class MainWindowViewController: NSViewController {
    private enum SidebarMetrics {
        static let minWidth: CGFloat = 180
        static let maxWidth: CGFloat = 300
        static let contentMinWidth: CGFloat = 620
    }

    private let settings = SettingsService()
    private let accessPolicy = SandboxFileAccessPolicy.current
    private lazy var fileSystem = FileSystemService(accessPolicy: accessPolicy)
    private lazy var fileOperations = FileOperationService(accessPolicy: accessPolicy)
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
    private let commandBar = CommandBarView()

    private let rootSplitView = NSSplitView()
    private let contentSplitView = NSSplitView()
    private let paneSplitView = MinimalDividerSplitView()
    private let mainStack = NSView()
    private weak var toolbarSearchField: NSSearchField?
    private weak var sidebarToolbarItem: NSToolbarItem?
    private var activeFilterText = ""
    private var settingsWindowController: NSWindowController?
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
    private var isFileOperationActive = false {
        didSet { setConflictingFileActionsEnabled(!isFileOperationActive) }
    }

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
        ExperimentalFlags.ensureAppSandboxRootExists()
        buildLayout()
        bindPaneCallbacks()
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
        if settings.isTerminalVisible {
            installTerminalPanel()
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
            self?.targetPane().currentDirectory ?? ExperimentalFlags.appSandboxRoot
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
        leftPane.setActive(activePaneID == .left)
        rightPane.setActive(activePaneID == .right)
        terminal.suggestedWorkingDirectory = targetPane().currentDirectory
        leftPane.setSearchQuery(activePaneID == .left ? activeFilterText : "")
        rightPane.setSearchQuery(activePaneID == .right ? activeFilterText : "")
        targetPane().focusDefaultRowForActivation()
        if view.window?.firstResponder !== toolbarSearchField {
            view.window?.makeFirstResponder(targetPane().tableView)
        }
    }

    private func performCommand(_ command: MainCommand) {
        guard !isFileOperationActive || !command.conflictsWithFileOperation else {
            showError(message: "Operation in Progress", detail: "Wait for the current file operation to finish before starting another file-changing action.")
            return
        }

        switch command {
        case .open:
            targetPane().openFocusedItem()
        case .newFile:
            promptForNewFile()
        case .newFolder:
            promptForNewFolder()
        case .rename:
            promptForRename()
        case .copy:
            copySelectedItems()
        case .move:
            moveSelectedItems()
        case .trash:
            confirmDeleteSelectedItems()
        case .refresh:
            targetPane().loadDirectory()
        case .toggleHiddenFiles:
            targetPane().toggleHiddenFiles()
        case .sortByName:
            targetPane().setSort(.name)
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
        case .home:
            targetPane().navigate(to: ExperimentalFlags.appSandboxRoot)
        case .downloads:
            targetPane().navigate(to: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Downloads", isDirectory: true))
        case .applications:
            targetPane().navigate(to: ExperimentalFlags.appSandboxRoot)
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
        let plain = !command && !shift && !option && !control
        let shiftOnly = shift && !command && !option && !control
        if event.keyCode == 53 {
            view.window?.makeFirstResponder(targetPane().tableView)
            return true
        }
        if command && event.keyCode == 48 {
            return false
        }
        if isTextInputFirstResponder, !(command && event.keyCode == 50) {
            return false
        }
        if command && !shift && !option && !control && event.keyCode == 50 {
            performCommand(.toggleTerminal)
            return true
        }
        if command && !shift && !option && !control && event.keyCode == 17 {
            performCommand(.togglePaneLayout)
            return true
        }
        if plain && event.keyCode == 48 {
            performCommand(.switchPane)
            return true
        }
        if shiftOnly && event.keyCode == 98 {
            performCommand(.newFile)
            return true
        }
        if plain && event.keyCode == 98 {
            performCommand(.newFolder)
            return true
        }
        if plain && event.keyCode == 120 {
            performCommand(.rename)
            return true
        }
        if plain && event.keyCode == 96 {
            performCommand(.copy)
            return true
        }
        if plain && event.keyCode == 97 {
            performCommand(.move)
            return true
        }
        if plain && event.keyCode == 100 {
            performCommand(.trash)
            return true
        }
        if command && !shift && !option && !control && event.keyCode == 15 {
            performCommand(.refresh)
            return true
        }
        if command && shift && !option && !control && event.keyCode == 123 {
            performCommand(.focusLeftPane)
            return true
        }
        if command && shift && !option && !control && event.keyCode == 124 {
            performCommand(.focusRightPane)
            return true
        }
        if command && option && !shift && !control && event.keyCode == 37 {
            performCommand(.downloads)
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
}

extension MainWindowViewController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search"
            item.searchField.placeholderString = "Filter active pane"
            item.searchField.target = self
            item.searchField.action = #selector(toolbarSearchChanged(_:))
            item.searchField.sendsSearchStringImmediately = true
            toolbarSearchField = item.searchField
            return item
        case .back:
            return toolbarItem(itemIdentifier, label: "Back", symbol: "chevron.left", action: #selector(toolbarBack(_:)))
        case .forward:
            return toolbarItem(itemIdentifier, label: "Forward", symbol: "chevron.right", action: #selector(toolbarForward(_:)))
        case .toggleTerminal:
            return toolbarItem(itemIdentifier, label: "Terminal", symbol: "terminal", action: #selector(toolbarToggleTerminal(_:)))
        case .toggleSidebar:
            let item = toolbarItem(itemIdentifier, label: "Sidebar", symbol: "sidebar.right", action: #selector(toolbarToggleSidebar(_:)))
            sidebarToolbarItem = item
            updateSidebarToolbarItem()
            return item
        case .viewOptions:
            return toolbarItem(itemIdentifier, label: "View", symbol: "line.3.horizontal.decrease.circle", action: #selector(toolbarViewOptions(_:)))
        case .settings:
            return toolbarItem(itemIdentifier, label: "Settings", symbol: "gearshape", action: #selector(toolbarSettings(_:)))
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

    private func presentSettings(_ sender: Any?) {
        if let existingWindow = settingsWindowController?.window, existingWindow.isVisible {
            sizeAndPositionSettingsWindow(existingWindow, preferredContentSize: existingWindow.contentViewController?.preferredContentSize ?? NSSize(width: 680, height: 500))
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let controller = SettingsViewController(settings: settings)
        controller.onChange = { [weak self] in self?.applySettingsChanges() }
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
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

    private func applySettingsChanges() {
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        setSidebarVisible(settings.defaultSidebarVisible)
        if settings.defaultTerminalVisible != isTerminalInstalled {
            settings.defaultTerminalVisible ? installTerminalPanel() : removeTerminalPanel()
        }
        setSinglePaneMode(settings.defaultSinglePaneMode, focusPane: activePaneID)
        leftPane.setShowsHiddenFiles(settings.showHiddenFilesByDefault)
        rightPane.setShowsHiddenFiles(settings.showHiddenFilesByDefault)
        leftPane.setSort(settings.defaultSortDescriptor.key, ascending: settings.defaultSortDescriptor.ascending)
        rightPane.setSort(settings.defaultSortDescriptor.key, ascending: settings.defaultSortDescriptor.ascending)
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
        let menu = NSMenu(title: "View Options")
        menu.addItem(menuItem("Refresh", action: #selector(menuRefresh(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Show Hidden Files", action: #selector(menuToggleHiddenFiles(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(menuItem("Sort by Name", action: #selector(menuSortByName(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Size", action: #selector(menuSortBySize(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Sort by Modified", action: #selector(menuSortByModified(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(menuItem("Ascending", action: #selector(menuSortAscending(_:)), key: "", modifiers: []))
        menu.addItem(menuItem("Descending", action: #selector(menuSortDescending(_:)), key: "", modifiers: []))
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
        if isTerminalInstalled {
            removeTerminalPanel()
            settings.isTerminalVisible = false
            view.window?.makeFirstResponder(targetPane().tableView)
        } else {
            installTerminalPanel()
            settings.isTerminalVisible = true
            terminal.suggestedWorkingDirectory = targetPane().currentDirectory
            view.layoutSubtreeIfNeeded()
            contentSplitView.setPosition(max(220, contentSplitView.bounds.height - 180), ofDividerAt: 0)
            terminal.focusCommandField()
        }
    }

    private func installTerminalPanel() {
        guard !isTerminalInstalled else { return }
        contentSplitView.addArrangedSubview(terminal.view)
        if terminalHeightConstraint == nil {
            terminalHeightConstraint = terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        }
        terminalHeightConstraint?.isActive = true
        isTerminalInstalled = true
    }

    private func removeTerminalPanel() {
        guard isTerminalInstalled else { return }
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
        let label = isSidebarInstalled ? "Hide Sidebar" : "Show Sidebar"
        let symbol = isSidebarInstalled ? "sidebar.right" : "sidebar.left"
        item.label = label
        item.paletteLabel = "Sidebar"
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    }

    private func promptForNewFolder() {
        view.window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Create a folder in \(targetPane().currentDirectory.path)"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

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
        alert.messageText = "New File"
        alert.informativeText = "Create a file in \(targetPane().currentDirectory.path)"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

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
            let name = try FileNameValidator.validate(rawName, in: targetPane().currentDirectory)
            let destination = targetPane().currentDirectory.appendingPathComponent(name, isDirectory: true)
            try accessPolicy.validateAccess(to: destination)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            targetPane().loadDirectory(selecting: destination)
        } catch let error as FileNameValidator.ValidationError {
            showError(message: "Invalid Folder Name", detail: error.localizedDescription)
        } catch {
            showError(message: "Could Not Create Folder", detail: error.localizedDescription)
        }
    }

    private func createFile(named rawName: String) {
        do {
            let name = try FileNameValidator.validate(rawName, in: targetPane().currentDirectory)
            let destination = targetPane().currentDirectory.appendingPathComponent(name)
            try accessPolicy.validateAccess(to: destination)
            try Data().write(to: destination, options: .withoutOverwriting)
            targetPane().loadDirectory(selecting: destination)
        } catch let error as FileNameValidator.ValidationError {
            showError(message: "Invalid File Name", detail: error.localizedDescription)
        } catch {
            showError(message: "Could Not Create File", detail: error.localizedDescription)
        }
    }

    private func promptForRename() {
        guard let item = targetPane().focusedItem else {
            showError(message: "Nothing Selected", detail: "Select one item to rename.")
            return
        }

        view.window?.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = item.url.path
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

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
        do {
            let parentDirectory = item.url.deletingLastPathComponent()
            let name = try FileNameValidator.validate(rawName, in: parentDirectory, replacing: item.url)
            let destination = parentDirectory.appendingPathComponent(name, isDirectory: item.isDirectory)
            try accessPolicy.validateAccess(to: destination)
            try FileManager.default.moveItem(at: item.url, to: destination)
            targetPane().loadDirectory(selecting: destination)
        } catch let error as FileNameValidator.ValidationError {
            showError(message: "Invalid Name", detail: error.localizedDescription)
        } catch {
            showError(message: "Could Not Rename Item", detail: error.localizedDescription)
        }
    }

    private func confirmDeleteSelectedItems() {
        let items = targetPane().selectedItems
        guard !items.isEmpty else {
            showError(message: "Nothing Selected", detail: "Select one or more items to delete.")
            return
        }
        let permanentlyDelete = settings.permanentlyDeleteInsteadOfTrash
        let operationName = permanentlyDelete ? "Permanently Delete" : "Move to Trash"
        let confirmButtonTitle = permanentlyDelete ? "Delete" : "Move to Trash"
        guard settings.confirmDeleteOperations else {
            delete(items: items, permanently: permanentlyDelete)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(operationName)?"
        alert.informativeText = confirmationSummary(
            operationName: operationName,
            urls: items.map(\.url),
            destinationDirectory: nil
        )
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.delete(items: items, permanently: permanentlyDelete)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func delete(items: [FileItem], permanently: Bool) {
        let operationName = permanently ? "Permanently Delete" : "Move to Trash"
        startFileOperation(named: operationName) { [fileOperations] progressHandler in
            if permanently {
                return try await fileOperations.delete(items.map(\.url), progressHandler: progressHandler)
            }
            return try await fileOperations.trash(items.map(\.url), progressHandler: progressHandler)
        }
    }

    private func copySelectedItems() {
        performFileTransfer(kind: "Copy", shouldConfirm: settings.confirmCopyOperations) { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.copy(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func moveSelectedItems() {
        performFileTransfer(kind: "Move", shouldConfirm: settings.confirmMoveOperations) { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.move(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func performFileTransfer(
        kind: String,
        shouldConfirm: Bool,
        operation: @escaping (FileOperationRequest, @escaping FileConflictHandler, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected", detail: "Select one or more items in the active pane.")
            return
        }

        let destinationDirectory = targetPane(useInactive: true).currentDirectory
        let request = FileOperationRequest(sources: sources, destinationDirectory: destinationDirectory)
        let start: () -> Void = { [weak self] in
            self?.startFileOperation(named: kind) { [weak self] progressHandler in
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

    private func transferDroppedItems(_ urls: [URL], to destinationDirectory: URL, copy: Bool) {
        guard !urls.isEmpty else { return }
        guard !isFileOperationActive else {
            showError(message: "Operation in Progress", detail: "Wait for the current file operation to finish before starting another file-changing action.")
            return
        }

        let kind = copy ? "Copy" : "Move"
        let request = FileOperationRequest(sources: urls, destinationDirectory: destinationDirectory)
        let start: () -> Void = { [weak self, fileOperations] in
            self?.startFileOperation(named: kind) { [weak self] progressHandler in
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

    private func confirmFileOperation(
        _ operationName: String,
        urls: [URL],
        destinationDirectory: URL?,
        confirmButtonTitle: String,
        completion: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let itemLabel = urls.count == 1 ? "Item" : "\(urls.count) Items"
        alert.messageText = "\(operationName) \(itemLabel)?"
        alert.informativeText = confirmationSummary(
            operationName: operationName,
            urls: urls,
            destinationDirectory: destinationDirectory
        )
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            completion()
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func confirmationSummary(operationName: String, urls: [URL], destinationDirectory: URL?) -> String {
        let itemLabel = urls.count == 1 ? "1 item" : "\(urls.count) items"
        var lines = ["\(operationName) \(itemLabel):"]
        let visibleNames = urls.prefix(8).map { "- \($0.lastPathComponent)" }
        lines.append(contentsOf: visibleNames)
        if urls.count > visibleNames.count {
            lines.append("- ...and \(urls.count - visibleNames.count) more")
        }
        if let destinationDirectory {
            lines.append("")
            lines.append("Destination: \(destinationDirectory.path)")
        }
        return lines.joined(separator: "\n")
    }

    private func startFileOperation(named operationName: String, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult) {
        guard !isFileOperationActive else { return }
        let previousWindowTitle = view.window?.title
        isFileOperationActive = true
        activeOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if let previousWindowTitle {
                    self.view.window?.title = previousWindowTitle
                }
                self.commandBar.clearOperationStatus()
                self.isFileOperationActive = false
                self.activeOperationTask = nil
            }

            do {
                let result = try await operation { [weak self] progress in
                    self?.updateFileOperationProgress(progress, operationName: operationName)
                }
                self.refreshBothPanes()
                self.showOperationResult(result, operationName: operationName)
            } catch {
                self.showError(message: "Could Not \(operationName) Items", detail: error.localizedDescription)
            }
        }
    }

    private func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String) {
        let status = "\(operationName): \(progress.currentItemName) (\(progress.completedCount)/\(progress.totalCount))"
        view.window?.title = status
        commandBar.setOperationStatus(status)
    }

    private func showOperationResult(_ result: FileOperationResult, operationName: String) {
        guard !result.succeededCompletely else { return }
        var details = [
            "Completed: \(result.completedItems.count)",
            "Skipped: \(result.skippedItems.count)",
            "Failed: \(result.failedItems.count)"
        ]
        if result.wasCancelled { details.append("The operation was cancelled before all items completed.") }
        details.append(contentsOf: result.failedItems.map { "\($0.url.lastPathComponent): \($0.error.localizedDescription)" })
        showError(message: "\(operationName) Finished With Issues", detail: details.joined(separator: "\n"))
    }

    private func setConflictingFileActionsEnabled(_ isEnabled: Bool) {
        commandBar.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }.forEach { button in
            guard let rawValue = button.identifier?.rawValue, let action = CommandBarAction(rawValue: rawValue) else { return }
            button.isEnabled = !MainCommand(commandBarAction: action).conflictsWithFileOperation || isEnabled
        }
    }

    @MainActor
    private func promptForConflict(destination: URL, operationName: String) async -> FileConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(destination.lastPathComponent) Already Exists"
        alert.informativeText = "\(operationName) would replace an item in \(destination.deletingLastPathComponent().path)."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .replace)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .skip)
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showError(message: message, detail: detail)
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
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
        guard let window = notification.object as? NSWindow, window === settingsWindowController?.window else { return }
        settingsWindowController = nil
        view.window?.makeKeyAndOrderFront(nil)
    }
}

extension MainWindowViewController: NSMenuItemValidation {
    @objc func menuNewFile(_ sender: Any?) { performCommand(.newFile) }
    @objc func menuNewFolder(_ sender: Any?) { performCommand(.newFolder) }
    @objc func menuRename(_ sender: Any?) { performCommand(.rename) }
    @objc func menuCopy(_ sender: Any?) { performCommand(.copy) }
    @objc func menuMove(_ sender: Any?) { performCommand(.move) }
    @objc func menuMoveToTrash(_ sender: Any?) { performCommand(.trash) }
    @objc func menuRefresh(_ sender: Any?) { performCommand(.refresh) }
    @objc func menuToggleHiddenFiles(_ sender: Any?) { performCommand(.toggleHiddenFiles) }
    @objc func menuSortByName(_ sender: Any?) { performCommand(.sortByName) }
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
    @objc func menuHome(_ sender: Any?) { performCommand(.home) }
    @objc func menuDownloads(_ sender: Any?) { performCommand(.downloads) }
    @objc func menuApplications(_ sender: Any?) { performCommand(.applications) }
    @objc func menuSwitchPane(_ sender: Any?) { performCommand(.switchPane) }
    @objc func menuFocusLeftPane(_ sender: Any?) { performCommand(.focusLeftPane) }
    @objc func menuFocusRightPane(_ sender: Any?) { performCommand(.focusRightPane) }
    @objc func menuSettings(_ sender: Any?) { presentSettings(sender) }

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
            menuItem.title = isSinglePaneMode ? "Use Dual Pane" : "Use Single Pane"
            menuItem.state = isSinglePaneMode ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuToggleHiddenFiles(_:)) {
            menuItem.state = targetPane().showsHiddenFiles ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuMoveToTrash(_:)) {
            menuItem.title = settings.permanentlyDeleteInsteadOfTrash ? "Permanently Delete" : "Move to Trash"
            return true
        }
        let sort = targetPane().sortDescriptor
        if menuItem.action == #selector(menuSortByName(_:)) {
            menuItem.state = sort.key == .name ? .on : .off
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
        return true
    }
}

private extension MainCommand {
    var conflictsWithFileOperation: Bool {
        switch self {
        case .newFile, .newFolder, .rename, .copy, .move, .trash:
            return true
        default:
            return false
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

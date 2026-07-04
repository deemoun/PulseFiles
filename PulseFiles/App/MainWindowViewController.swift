import AppKit

final class MainWindowViewController: NSViewController {
    private let settings = SettingsService()
    private let accessPolicy = SandboxFileAccessPolicy.current
    private lazy var fileSystem = FileSystemService(accessPolicy: accessPolicy)
    private lazy var fileOperations = FileOperationService(accessPolicy: accessPolicy)
    private let recentLocations = RecentLocationService()

    private lazy var leftPane = FilePaneViewController(
        paneID: .left,
        viewModel: FilePaneViewModel(initialDirectory: accessPolicy.validatedDirectory(settings.lastLeftDirectory), fileSystem: fileSystem, accessPolicy: accessPolicy)
    )
    private lazy var rightPane = FilePaneViewController(
        paneID: .right,
        viewModel: FilePaneViewModel(initialDirectory: accessPolicy.validatedDirectory(settings.lastRightDirectory), fileSystem: fileSystem, accessPolicy: accessPolicy)
    )
    private lazy var sidebar = SidebarViewController(recentLocations: recentLocations, accessPolicy: accessPolicy)
    private let terminal = TerminalViewController()
    private let commandBar = CommandBarView()

    private let rootSplitView = NSSplitView()
    private let contentSplitView = NSSplitView()
    private let paneSplitView = NSSplitView()
    private let mainStack = NSView()
    private weak var toolbarSearchField: NSSearchField?
    private var activeFilterText = ""
    private var didSetInitialSplitPositions = false
    private var keyEventMonitor: Any?
    private var sidebarMinWidthConstraint: NSLayoutConstraint?
    private var sidebarMaxWidthConstraint: NSLayoutConstraint?
    private var isTerminalInstalled = false
    private var terminalHeightConstraint: NSLayoutConstraint?

    private var activePaneID: PaneID = .left {
        didSet { updateActivePane() }
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
        installKeyEventMonitor()
        view.window?.makeFirstResponder(targetPane().tableView)
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
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
        rootSplitView.addArrangedSubview(sidebar.view)
        mainStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        sidebarMinWidthConstraint = sidebar.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        sidebarMaxWidthConstraint = sidebar.view.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        sidebarMinWidthConstraint?.isActive = settings.isSidebarVisible
        sidebarMaxWidthConstraint?.isActive = settings.isSidebarVisible
        sidebar.view.isHidden = !settings.isSidebarVisible

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
        paneSplitView.dividerStyle = .paneSplitter
        paneSplitView.delegate = self
        addChild(leftPane)
        addChild(rightPane)
        paneSplitView.addArrangedSubview(leftPane.view)
        paneSplitView.addArrangedSubview(rightPane.view)
        leftPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rightPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        contentSplitView.addArrangedSubview(paneSplitView)

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
        paneSplitView.setPosition(max(260, paneSplitView.bounds.width / 2), ofDividerAt: 0)
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
        if view.window?.firstResponder !== toolbarSearchField {
            view.window?.makeFirstResponder(targetPane().tableView)
        }
    }

    private func performCommand(_ command: MainCommand) {
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
        case .toggleTerminal:
            toggleTerminal()
        case .toggleSidebar:
            toggleSidebar()
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
        case .focusLeftPane:
            activePaneID = .left
        case .focusRightPane:
            activePaneID = .right
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleGlobalKeyDown(event) {
            targetPane().handleKeyDown(event)
        }
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            return self.handleGlobalKeyDown(event) ? nil : event
        }
    }

    private func handleGlobalKeyDown(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        if isTextInputFirstResponder, !(command && event.keyCode == 50) {
            return false
        }
        if command && event.keyCode == 50 {
            performCommand(.toggleTerminal)
            return true
        }
        if event.keyCode == 48 {
            performCommand(.switchPane)
            return true
        }
        if shift && event.keyCode == 98 {
            performCommand(.newFile)
            return true
        }
        if event.keyCode == 98 {
            performCommand(.newFolder)
            return true
        }
        if event.keyCode == 120 {
            performCommand(.rename)
            return true
        }
        if event.keyCode == 96 {
            performCommand(.copy)
            return true
        }
        if event.keyCode == 97 {
            performCommand(.move)
            return true
        }
        if event.keyCode == 100 {
            performCommand(.trash)
            return true
        }
        if command && event.keyCode == 15 {
            performCommand(.refresh)
            return true
        }
        if command && shift && event.keyCode == 123 {
            performCommand(.focusLeftPane)
            return true
        }
        if command && shift && event.keyCode == 124 {
            performCommand(.focusRightPane)
            return true
        }
        if command && option && event.keyCode == 37 {
            performCommand(.downloads)
            return true
        }

        return false
    }

    private var isTextInputFirstResponder: Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        return firstResponder is NSTextView || firstResponder is NSTextField
    }
}

extension MainWindowViewController: NSToolbarDelegate {
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
            return toolbarItem(itemIdentifier, label: "Sidebar", symbol: "sidebar.right", action: #selector(toolbarToggleSidebar(_:)))
        case .viewOptions:
            return toolbarItem(itemIdentifier, label: "View", symbol: "line.3.horizontal.decrease.circle", action: #selector(toolbarUnavailable(_:)))
        case .settings:
            return toolbarItem(itemIdentifier, label: "Settings", symbol: "gearshape", action: #selector(toolbarUnavailable(_:)))
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

    @objc private func toolbarUnavailable(_ sender: Any?) {
        NSSound.beep()
    }

    @objc private func toolbarSearchChanged(_ sender: NSSearchField) {
        activeFilterText = sender.stringValue
        targetPane().setSearchQuery(activeFilterText)
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
        setSidebarVisible(sidebar.view.isHidden)
    }

    private func setSidebarVisible(_ visible: Bool) {
        sidebarMinWidthConstraint?.isActive = visible
        sidebarMaxWidthConstraint?.isActive = visible
        sidebar.view.isHidden = !visible
        settings.isSidebarVisible = visible
        view.layoutSubtreeIfNeeded()
        applySidebarSplitPosition()
    }

    private func applySidebarSplitPosition() {
        guard rootSplitView.arrangedSubviews.count > 1 else { return }
        if sidebar.view.isHidden {
            rootSplitView.setPosition(rootSplitView.bounds.width, ofDividerAt: 0)
        } else {
            rootSplitView.setPosition(max(620, rootSplitView.bounds.width - 220), ofDividerAt: 0)
        }
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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            showError(message: "Invalid Folder Name", detail: "Folder names cannot be empty or contain slashes.")
            return
        }

        let destination = targetPane().currentDirectory.appendingPathComponent(name, isDirectory: true)
        do {
            try accessPolicy.validateAccess(to: destination)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            targetPane().loadDirectory()
        } catch {
            showError(message: "Could Not Create Folder", detail: error.localizedDescription)
        }
    }

    private func createFile(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            showError(message: "Invalid File Name", detail: "File names cannot be empty or contain slashes.")
            return
        }

        let destination = targetPane().currentDirectory.appendingPathComponent(name)
        do {
            try accessPolicy.validateAccess(to: destination)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                showError(message: "File Already Exists", detail: destination.lastPathComponent)
                return
            }
            try Data().write(to: destination, options: .withoutOverwriting)
            targetPane().loadDirectory()
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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            showError(message: "Invalid Name", detail: "Names cannot be empty or contain slashes.")
            return
        }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: item.isDirectory)
        do {
            try accessPolicy.validateAccess(to: destination)
            try FileManager.default.moveItem(at: item.url, to: destination)
            targetPane().loadDirectory()
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

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move to Trash?"
        alert.informativeText = items.map(\.displayName).joined(separator: "\n")
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.trash(items: items)
        }

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func trash(items: [FileItem]) {
        do {
            for item in items {
                try accessPolicy.validateAccess(to: item.url)
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
            }
            targetPane().loadDirectory()
        } catch {
            showError(message: "Could Not Move Item to Trash", detail: error.localizedDescription)
        }
    }

    private func copySelectedItems() {
        performFileTransfer(kind: "Copy") { [fileOperations] request, conflictHandler in
            try fileOperations.copy(request, conflictHandler: conflictHandler)
        }
    }

    private func moveSelectedItems() {
        performFileTransfer(kind: "Move") { [fileOperations] request, conflictHandler in
            try fileOperations.move(request, conflictHandler: conflictHandler)
        }
    }

    private func performFileTransfer(kind: String, operation: (FileOperationRequest, (URL) -> FileConflictResolution) throws -> Void) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected", detail: "Select one or more items in the active pane.")
            return
        }

        let destinationDirectory = targetPane(useInactive: true).currentDirectory
        let request = FileOperationRequest(sources: sources, destinationDirectory: destinationDirectory)
        do {
            try operation(request) { [weak self] destination in
                self?.promptForConflict(destination: destination, operationName: kind) ?? .cancel
            }
            refreshBothPanes()
        } catch {
            showError(message: "Could Not \(kind) Items", detail: error.localizedDescription)
        }
    }

    private func promptForConflict(destination: URL, operationName: String) -> FileConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(destination.lastPathComponent) Already Exists"
        alert.informativeText = "\(operationName) would replace an item in \(destination.deletingLastPathComponent().path)."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .skip
        default:
            return .cancel
        }
    }

    private func refreshBothPanes() {
        leftPane.loadDirectory()
        rightPane.loadDirectory()
    }

    private func showError(message: String, detail: String) {
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
            return 620
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
            if sidebar.view.isHidden {
                return splitView.bounds.width
            }
            return max(620, splitView.bounds.width - 180)
        case paneSplitView:
            return max(260, splitView.bounds.width - 260)
        case contentSplitView:
            return max(220, splitView.bounds.height - 120)
        default:
            return proposedMaximumPosition
        }
    }
}

extension MainWindowViewController {
    @objc func menuNewFile(_ sender: Any?) { performCommand(.newFile) }
    @objc func menuNewFolder(_ sender: Any?) { performCommand(.newFolder) }
    @objc func menuRename(_ sender: Any?) { performCommand(.rename) }
    @objc func menuCopy(_ sender: Any?) { performCommand(.copy) }
    @objc func menuMove(_ sender: Any?) { performCommand(.move) }
    @objc func menuMoveToTrash(_ sender: Any?) { performCommand(.trash) }
    @objc func menuRefresh(_ sender: Any?) { performCommand(.refresh) }
    @objc func menuToggleTerminal(_ sender: Any?) { performCommand(.toggleTerminal) }
    @objc func menuToggleSidebar(_ sender: Any?) { performCommand(.toggleSidebar) }
    @objc func menuBack(_ sender: Any?) { performCommand(.back) }
    @objc func menuForward(_ sender: Any?) { performCommand(.forward) }
    @objc func menuParent(_ sender: Any?) { performCommand(.parent) }
    @objc func menuHome(_ sender: Any?) { performCommand(.home) }
    @objc func menuDownloads(_ sender: Any?) { performCommand(.downloads) }
    @objc func menuApplications(_ sender: Any?) { performCommand(.applications) }
    @objc func menuSwitchPane(_ sender: Any?) { performCommand(.switchPane) }
    @objc func menuFocusLeftPane(_ sender: Any?) { performCommand(.focusLeftPane) }
    @objc func menuFocusRightPane(_ sender: Any?) { performCommand(.focusRightPane) }
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

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
    private weak var sidebarToolbarItem: NSToolbarItem?
    private var activeFilterText = ""
    private var didSetInitialSplitPositions = false
    private var keyEventMonitor: Any?
    private var sidebarMinWidthConstraint: NSLayoutConstraint?
    private var sidebarMaxWidthConstraint: NSLayoutConstraint?
    private var isSidebarInstalled = false
    private var isTerminalInstalled = false
    private var terminalHeightConstraint: NSLayoutConstraint?
    private var activeOperationTask: Task<Void, Never>?
    private var isFileOperationActive = false {
        didSet { setConflictingFileActionsEnabled(!isFileOperationActive) }
    }

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
        settings.sidebarWidth = Double(clampedSidebarWidth(rootSplitView.bounds.width - rootSplitView.positionOfDivider(at: 0)))
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
            targetPane().loadDirectory()
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
            targetPane().loadDirectory()
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
            targetPane().loadDirectory()
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
        startFileOperation(named: "Move to Trash") { [fileOperations] progressHandler in
            try await fileOperations.trash(items.map(\.url), progressHandler: progressHandler)
        }
    }

    private func copySelectedItems() {
        performFileTransfer(kind: "Copy") { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.copy(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func moveSelectedItems() {
        performFileTransfer(kind: "Move") { [fileOperations] request, conflictHandler, progressHandler in
            try await fileOperations.move(request, conflictHandler: conflictHandler, progressHandler: progressHandler)
        }
    }

    private func performFileTransfer(
        kind: String,
        operation: @escaping (FileOperationRequest, @escaping (URL) -> FileConflictResolution, FileOperationProgressHandler?) async throws -> FileOperationResult
    ) {
        let sources = targetPane().selectedItems.map(\.url)
        guard !sources.isEmpty else {
            showError(message: "Nothing Selected", detail: "Select one or more items in the active pane.")
            return
        }

        let destinationDirectory = targetPane(useInactive: true).currentDirectory
        let request = FileOperationRequest(sources: sources, destinationDirectory: destinationDirectory)
        startFileOperation(named: kind) { [weak self] progressHandler in
            try await operation(request, { destination in
                self?.promptForConflict(destination: destination, operationName: kind) ?? .cancel
            }, progressHandler)
        }
    }

    private func startFileOperation(named operationName: String, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult) {
        guard !isFileOperationActive else { return }
        isFileOperationActive = true
        activeOperationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await operation { [weak self] progress in
                    self?.updateFileOperationProgress(progress, operationName: operationName)
                }
                self.refreshBothPanes()
                self.showOperationResult(result, operationName: operationName)
            } catch {
                self.showError(message: "Could Not \(operationName) Items", detail: error.localizedDescription)
            }
            self.isFileOperationActive = false
            self.activeOperationTask = nil
        }
    }

    private func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String) {
        view.window?.title = "\(operationName): \(progress.currentItemName) (\(progress.completedCount)/\(progress.totalCount))"
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

extension MainWindowViewController: NSMenuItemValidation {
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(menuToggleSidebar(_:)) {
            menuItem.state = isSidebarInstalled ? .on : .off
            return true
        }
        if menuItem.action == #selector(menuToggleTerminal(_:)) {
            menuItem.state = isTerminalInstalled ? .on : .off
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

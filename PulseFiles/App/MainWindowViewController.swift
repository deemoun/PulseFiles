import AppKit

final class MainWindowViewController: NSViewController {
    private let settings = SettingsService()
    private let accessPolicy = SandboxFileAccessPolicy.current
    private lazy var fileSystem = FileSystemService(accessPolicy: accessPolicy)
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
    private var didSetInitialSplitPositions = false
    private var keyEventMonitor: Any?

    private var activePaneID: PaneID = .left {
        didSet { updateActivePane() }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
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
        rootSplitView.dividerStyle = .thin
        rootSplitView.delegate = self
        rootSplitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootSplitView)
        NSLayoutConstraint.activate([
            rootSplitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootSplitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootSplitView.topAnchor.constraint(equalTo: view.topAnchor),
            rootSplitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        mainStack.translatesAutoresizingMaskIntoConstraints = false
        rootSplitView.addArrangedSubview(mainStack)
        addChild(sidebar)
        rootSplitView.addArrangedSubview(sidebar.view)
        mainStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        sidebar.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        sidebar.view.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        sidebar.view.isHidden = !settings.isSidebarVisible

        contentSplitView.isVertical = false
        contentSplitView.dividerStyle = .thin
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
            commandBar.heightAnchor.constraint(equalToConstant: 40)
        ])

        paneSplitView.isVertical = true
        paneSplitView.dividerStyle = .thin
        paneSplitView.delegate = self
        addChild(leftPane)
        addChild(rightPane)
        paneSplitView.addArrangedSubview(leftPane.view)
        paneSplitView.addArrangedSubview(rightPane.view)
        leftPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rightPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        contentSplitView.addArrangedSubview(paneSplitView)

        addChild(terminal)
        contentSplitView.addArrangedSubview(terminal.view)
        terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        terminal.view.isHidden = !settings.isTerminalVisible
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didSetInitialSplitPositions, view.bounds.width > 0, view.bounds.height > 0 else { return }
        didSetInitialSplitPositions = true
        rootSplitView.setPosition(max(620, rootSplitView.bounds.width - 220), ofDividerAt: 0)
        paneSplitView.setPosition(max(260, paneSplitView.bounds.width / 2), ofDividerAt: 0)
        if !terminal.view.isHidden {
            contentSplitView.setPosition(max(220, contentSplitView.bounds.height - 180), ofDividerAt: 0)
        }
    }

    private func bindPaneCallbacks() {
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
        }
        rightPane.onDirectoryChanged = { [weak self] url in
            self?.settings.lastRightDirectory = url
            self?.recentLocations.record(url)
        }
        sidebar.onOpenLocation = { [weak self] url, useInactive in
            self?.targetPane(useInactive: useInactive).navigate(to: url)
        }
        commandBar.onAction = { [weak self] action in
            self?.performCommand(action)
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
        view.window?.makeFirstResponder(targetPane().tableView)
    }

    private func performCommand(_ action: CommandBarAction) {
        switch action {
        case .open:
            targetPane().openFocusedItem()
        case .newFile:
            promptForNewFile()
        case .newFolder:
            promptForNewFolder()
        case .rename:
            promptForRename()
        case .delete:
            confirmDeleteSelectedItems()
        case .view, .edit, .copy, .move, .more:
            showUnavailable(action.rawValue)
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
        if command && event.keyCode == 50 {
            toggleTerminal()
            return true
        }
        if event.keyCode == 48 {
            activePaneID = activePaneID.opposite
            return true
        }
        if shift && event.keyCode == 98 {
            promptForNewFile()
            return true
        }
        if event.keyCode == 98 {
            promptForNewFolder()
            return true
        }
        if event.keyCode == 120 {
            promptForRename()
            return true
        }
        if event.keyCode == 100 {
            confirmDeleteSelectedItems()
            return true
        }
        if command && event.keyCode == 15 {
            targetPane().loadDirectory()
            return true
        }
        if command && shift && event.keyCode == 123 {
            activePaneID = .left
            return true
        }
        if command && shift && event.keyCode == 124 {
            activePaneID = .right
            return true
        }
        if command && option && event.keyCode == 37 {
            targetPane().navigate(to: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Downloads", isDirectory: true))
            return true
        }

        return false
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
        item.target = self
        item.action = action
        return item
    }

    @objc private func toolbarBack(_ sender: Any?) {
        targetPane().goBack()
    }

    @objc private func toolbarForward(_ sender: Any?) {
        targetPane().goForward()
    }

    @objc private func toolbarToggleTerminal(_ sender: Any?) {
        toggleTerminal()
    }

    @objc private func toolbarToggleSidebar(_ sender: Any?) {
        toggleSidebar()
    }

    @objc private func toolbarUnavailable(_ sender: Any?) {
        NSSound.beep()
    }

    private func toggleTerminal() {
        terminal.view.isHidden.toggle()
        settings.isTerminalVisible = !terminal.view.isHidden
        if !terminal.view.isHidden {
            terminal.suggestedWorkingDirectory = targetPane().currentDirectory
            view.layoutSubtreeIfNeeded()
            contentSplitView.setPosition(max(220, contentSplitView.bounds.height - 180), ofDividerAt: 0)
            terminal.focusCommandField()
        } else {
            view.window?.makeFirstResponder(targetPane().tableView)
        }
    }

    private func toggleSidebar() {
        sidebar.view.isHidden.toggle()
        settings.isSidebarVisible = !sidebar.view.isHidden
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

    private func showUnavailable(_ action: String) {
        showError(message: "\(action) Is Not Implemented Yet", detail: "This control is wired, but the operation is still scheduled for the next implementation phase.")
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

private extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("PulseFilesToolbarBack")
    static let forward = NSToolbarItem.Identifier("PulseFilesToolbarForward")
    static let search = NSToolbarItem.Identifier("PulseFilesToolbarSearch")
    static let toggleTerminal = NSToolbarItem.Identifier("PulseFilesToolbarTerminal")
    static let toggleSidebar = NSToolbarItem.Identifier("PulseFilesToolbarSidebar")
    static let viewOptions = NSToolbarItem.Identifier("PulseFilesToolbarViewOptions")
    static let settings = NSToolbarItem.Identifier("PulseFilesToolbarSettings")
}

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

    private func buildLayout() {
        rootSplitView.isVertical = true
        rootSplitView.dividerStyle = .thin
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
        sidebar.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        sidebar.view.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        contentSplitView.isVertical = false
        contentSplitView.dividerStyle = .thin
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
        addChild(leftPane)
        addChild(rightPane)
        paneSplitView.addArrangedSubview(leftPane.view)
        paneSplitView.addArrangedSubview(rightPane.view)
        contentSplitView.addArrangedSubview(paneSplitView)

        addChild(terminal)
        contentSplitView.addArrangedSubview(terminal.view)
        terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        terminal.view.isHidden = !settings.isTerminalVisible
    }

    private func bindPaneCallbacks() {
        leftPane.onActivate = { [weak self] in self?.activePaneID = .left }
        rightPane.onActivate = { [weak self] in self?.activePaneID = .right }
        leftPane.onSwitchPane = { [weak self] in self?.activePaneID = .right }
        rightPane.onSwitchPane = { [weak self] in self?.activePaneID = .left }
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
        case .newFile, .newFolder, .rename, .view, .edit, .copy, .move, .delete, .more:
            NSSound.beep()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            activePaneID = activePaneID.opposite
            return
        }
        targetPane().handleKeyDown(event)
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
            return toolbarItem(itemIdentifier, label: "Back", symbol: "chevron.left") { [weak self] in self?.targetPane().goBack() }
        case .forward:
            return toolbarItem(itemIdentifier, label: "Forward", symbol: "chevron.right") { [weak self] in self?.targetPane().goForward() }
        case .toggleTerminal:
            return toolbarItem(itemIdentifier, label: "Terminal", symbol: "terminal") { [weak self] in self?.toggleTerminal() }
        case .toggleSidebar:
            return toolbarItem(itemIdentifier, label: "Sidebar", symbol: "sidebar.right") { [weak self] in self?.toggleSidebar() }
        case .viewOptions:
            return toolbarItem(itemIdentifier, label: "View", symbol: "line.3.horizontal.decrease.circle") {}
        case .settings:
            return toolbarItem(itemIdentifier, label: "Settings", symbol: "gearshape") {}
        default:
            return nil
        }
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: @escaping () -> Void) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = ClosureSleeve.shared
        item.action = ClosureSleeve.shared.register(action)
        return item
    }

    private func toggleTerminal() {
        terminal.view.isHidden.toggle()
        settings.isTerminalVisible = !terminal.view.isHidden
    }

    private func toggleSidebar() {
        sidebar.view.isHidden.toggle()
        settings.isSidebarVisible = !sidebar.view.isHidden
    }
}

private final class ClosureSleeve: NSObject {
    static let shared = ClosureSleeve()
    private var actions: [Selector: () -> Void] = [:]

    func register(_ action: @escaping () -> Void) -> Selector {
        let selector = NSSelectorFromString("action\(actions.count):")
        actions[selector] = action
        return selector
    }

    override func responds(to aSelector: Selector!) -> Bool {
        actions[aSelector] != nil || super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        actions[aSelector] == nil ? super.forwardingTarget(for: aSelector) : self
    }

    @objc func action0(_ sender: Any?) { actions[#selector(action0(_:))]?() }
    @objc func action1(_ sender: Any?) { actions[#selector(action1(_:))]?() }
    @objc func action2(_ sender: Any?) { actions[#selector(action2(_:))]?() }
    @objc func action3(_ sender: Any?) { actions[#selector(action3(_:))]?() }
    @objc func action4(_ sender: Any?) { actions[#selector(action4(_:))]?() }
    @objc func action5(_ sender: Any?) { actions[#selector(action5(_:))]?() }
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

import AppKit

struct DropTransferPolicy {
    enum Operation {
        case copy
        case move
    }

    typealias VolumeIdentifierProvider = (URL) -> String?

    var volumeIdentifierProvider: VolumeIdentifierProvider = { (url: URL) -> String? in
        let values = try? url.resourceValues(forKeys: [.volumeURLKey])
        return (values?.allValues[.volumeURLKey] as? URL)
            .map { $0.standardizedFileURL.path }
    }

    func resolvedOperation(for sources: [URL], destinationDirectory: URL, isInternalAppDrag: Bool, optionForcesCopy: Bool) -> Operation {
        guard !optionForcesCopy, isInternalAppDrag, !sources.isEmpty else { return .copy }
        guard sourcesShareVolume(with: destinationDirectory, sources: sources) else { return .copy }
        return .move
    }

    func sourcesShareVolume(with destinationDirectory: URL, sources: [URL]) -> Bool {
        guard let destinationVolume = volumeIdentifierProvider(destinationDirectory) else { return false }
        return sources.allSatisfy { source in
            volumeIdentifierProvider(source) == destinationVolume
        }
    }
}

final class FilePaneViewController: NSViewController {
    private enum ColumnID {
        static let name = "name"
        static let kind = "kind"
        static let size = "size"
        static let modified = "modified"
    }

    private struct ColumnMetrics {
        let compactWidth: CGFloat
        let singlePaneMinimumWidth: CGFloat
        let singlePaneWeight: CGFloat
    }

    private static let columnMetrics: [String: ColumnMetrics] = [
        ColumnID.name: ColumnMetrics(compactWidth: 360, singlePaneMinimumWidth: 210, singlePaneWeight: 0.48),
        ColumnID.kind: ColumnMetrics(compactWidth: 140, singlePaneMinimumWidth: 120, singlePaneWeight: 0.18),
        ColumnID.size: ColumnMetrics(compactWidth: 90, singlePaneMinimumWidth: 100, singlePaneWeight: 0.14),
        ColumnID.modified: ColumnMetrics(compactWidth: 170, singlePaneMinimumWidth: 160, singlePaneWeight: 0.20)
    ]

    let paneID: PaneID
    let viewModel: FilePaneViewModel
    let tableView = FileTableView()

    var onActivate: (() -> Void)?
    var onSwitchPane: (() -> Void)?
    var onToggleTerminal: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onNewFile: (() -> Void)?
    var onCommand: ((MainCommand) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenWithApplication: ((URL, URL?) -> Void)?
    var onDropURLs: (([URL], URL, Bool) -> Void)?
    var onRenameItem: ((FileItem, String) -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?
    var onSelectionChanged: (([FileItem]) -> Void)?
    var onDirectoryAccessGranted: ((URL) -> Void)?

    private let header = NSVisualEffectView()
    private let breadcrumb = BreadcrumbView()
    private let directoryIcon = NSImageView()
    private let hiddenButton = NSButton()
    private let scrollView = NSScrollView()
    private let contentOverlay = PaneContentOverlayView()
    private let statusView = PaneStatusView()
    private let activeStripe = NSView()
    private var isReloadingData = false
    private var isPaneActive = false
    private var dimmedFileURLs = Set<String>()
    private var previousSelectedRowIndexes = IndexSet()
    /// URLs survive sorting, filtering, and monitor-driven reloads; row indexes do not.
    private var previousSelectionURLs: [URL] = []
    private var pendingSelectionURL: URL?
    private var inlineRenameRow: Int?
    /// The item snapshot remains valid while a refresh is deferred, even when
    /// filtering, sorting, or navigation has already changed the view model.
    private var inlineRenameItem: FileItem?
    private var inlineRenameSession = InlineRenameCommitSession()
    private var hasDeferredTableReload = false
    private var hasOppositePane = true
    private var lastAppliedColumnLayoutWidth: CGFloat = 0
    private var dualPaneGridStyleMask = NSTableView.GridLineStyle()
    private lazy var dropProbeCache = FileSystemProbeCache()
    private lazy var dropTransferPolicy = DropTransferPolicy(volumeIdentifierProvider: { [weak self] url in
        guard let self else { return nil }
        self.dropProbeCache.requestVolumeIdentifier(url)
        return self.dropProbeCache.volumeIdentifier(for: url)
    })
    private let accessGrantService = FolderAccessGrantService.shared
    private let openWithApplicationResolver: OpenWithMenuApplicationResolver
    private lazy var volumeStatusCache = VolumeStatusResolutionCache(directory: viewModel.currentDirectory)

    init(
        paneID: PaneID,
        viewModel: FilePaneViewModel,
        openWithApplicationResolver: OpenWithMenuApplicationResolver? = nil
    ) {
        self.paneID = paneID
        self.viewModel = viewModel
        self.openWithApplicationResolver = openWithApplicationResolver ?? OpenWithMenuApplicationResolver()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var currentDirectory: URL { viewModel.currentDirectory }
    var sortDescriptor: FileSortDescriptor { viewModel.sortDescriptor }
    var showsHiddenFiles: Bool { viewModel.showsHiddenFiles }
    var selectedItems: [FileItem] {
        tableView.selectedRowIndexes.compactMap { item(forRow: $0) }
    }

    var focusedItem: FileItem? {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : tableView.clickedRow
        return item(forRow: row)
    }

    private var parentURL: URL {
        viewModel.currentDirectory.deletingLastPathComponent()
    }

    private var canShowParentRow: Bool {
        guard viewModel.searchQuery.isEmpty else { return false }
        let current = viewModel.currentDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let root = ExperimentalFlags.appSandboxRoot.standardizedFileURL.resolvingSymlinksInPath().path
        return current != root && parentURL != viewModel.currentDirectory
    }

    private var realRowOffset: Int { canShowParentRow ? 1 : 0 }

    override func loadView() {
        let paneView = PaneContainerView()
        paneView.onMouseDown = { [weak self] in self?.onActivate?() }
        view = paneView
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.container(for: paneID))
        LiquidGlassStyle.applyPanelChrome(to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        volumeStatusCache.onChange = { [weak self] in self?.configureStatusView() }
        buildHeader()
        buildTable()
        buildLayout()
        bindViewModel()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyColumnLayout()
    }

    func loadDirectory(selecting url: URL? = nil, onLoaded: (() -> Void)? = nil) {
        pendingSelectionURL = url
        viewModel.loadCurrentDirectory { [weak self] in
            self?.selectPendingItemIfAvailable()
            onLoaded?()
        }
    }

    func selectItem(at url: URL) {
        pendingSelectionURL = url
        if !viewModel.isLoading {
            selectPendingItemIfAvailable()
        }
    }

    /// Selection commands intentionally operate only on real file rows; the
    /// synthetic parent row is navigation, not a filesystem item.
    func selectAllItems() {
        let rows = IndexSet(integersIn: realRowOffset..<tableView.numberOfRows)
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    func invertSelection() {
        let allRows = Set(realRowOffset..<tableView.numberOfRows)
        let inverted = IndexSet(allRows.subtracting(tableView.selectedRowIndexes))
        tableView.selectRowIndexes(inverted, byExtendingSelection: false)
    }

    func toggleHiddenFiles() {
        viewModel.toggleHiddenFiles()
    }

    func setShowsHiddenFiles(_ showsHiddenFiles: Bool) {
        viewModel.setShowsHiddenFiles(showsHiddenFiles)
    }

    func setSort(_ key: FileSortKey) {
        viewModel.setSort(key)
    }

    func setSort(_ key: FileSortKey, ascending: Bool) {
        viewModel.setSort(key, ascending: ascending)
    }

    func navigate(to url: URL) {
        viewModel.navigate(to: url)
    }

    /// Presents a user-initiated folder picker and stores a security-scoped
    /// grant before opening the selected directory.
    func chooseDirectoryForAccessRecovery() {
        chooseRecoveryDirectory()
    }

    /// Clears UI state before redirecting away from an unmounted directory.
    @discardableResult
    func fallBackIfCurrentDirectoryIsUnavailable() -> Bool {
        guard viewModel.fallBackIfCurrentDirectoryIsUnavailable() else { return false }
        pendingSelectionURL = nil
        previousSelectedRowIndexes = []
        previousSelectionURLs = []
        tableView.deselectAll(nil)
        onSelectionChanged?([])
        return true
    }

    /// Invalidates a directory snapshot and schedules its revalidation after a
    /// mount change. Callers must first handle unavailable directories.
    func revalidateAfterVolumeChange() {
        viewModel.reloadAfterExternalDirectoryChange()
    }

    func goBack() {
        viewModel.goBack()
    }

    func goForward() {
        viewModel.goForward()
    }

    func goParent() {
        viewModel.goParent()
    }

    func setActive(_ active: Bool) {
        guard isPaneActive != active else { return }
        isPaneActive = active
        updatePaneChrome()
        requestTableReload()
    }

    func setHasOppositePane(_ hasOppositePane: Bool) {
        self.hasOppositePane = hasOppositePane
        applyColumnLayout(force: true)
    }

    private func updatePaneChrome() {
        activeStripe.layer?.backgroundColor = isPaneActive ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = isPaneActive ? LiquidGlassStyle.activeStroke.cgColor : LiquidGlassStyle.panelStroke.cgColor
        view.layer?.backgroundColor = isPaneActive ? LiquidGlassStyle.activeFill.cgColor : LiquidGlassStyle.panelFill.cgColor
    }

    func focusDefaultRowForActivation() {
        selectDefaultRow()
        view.window?.makeFirstResponder(tableView)
    }

    func openFocusedItem() {
        if isParentRow(tableView.selectedRow >= 0 ? tableView.selectedRow : tableView.clickedRow) {
            goParent()
            return
        }
        guard let item = focusedItem else { return }
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            onOpenURL?(item.url)
        }
    }

    @discardableResult
    func beginInlineRename() -> Bool {
        guard selectedItems.count == 1, let item = focusedItem else { return false }
        guard let row = row(for: item), !isParentRow(row) else { return false }
        guard let nameColumn = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return false }
        inlineRenameRow = row
        inlineRenameItem = item
        inlineRenameSession.begin(for: item.url)
        updateInlineRenameField(at: row, for: item.url)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        view.window?.makeFirstResponder(tableView)
        tableView.editColumn(nameColumn, row: row, with: nil, select: true)
        selectFilenameStem(for: item)
        return true
    }

    func handleKeyDown(_ event: NSEvent) {
        tableView.keyDown(with: event)
    }

    func setSearchQuery(_ query: String) {
        viewModel.setSearchQuery(query)
    }

    func setDimmedFileURLs(_ urls: [URL]) {
        dimmedFileURLs = Set(urls.map(normalizedPath))
        requestTableReload()
    }

    private func buildHeader() {
        header.material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        header.blendingMode = .withinWindow
        header.state = .active

        directoryIcon.imageScaling = .scaleProportionallyDown
        directoryIcon.setContentHuggingPriority(.required, for: .horizontal)

        hiddenButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Toggle Hidden Files".localized)
        LiquidGlassStyle.applyButtonChrome(to: hiddenButton)
        hiddenButton.target = self
        hiddenButton.action = #selector(toggleHidden)
        hiddenButton.toolTip = "Toggle hidden files".localized

        breadcrumb.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.breadcrumb(for: paneID))
        breadcrumb.onSelect = { [weak self] url in self?.navigate(to: url) }
    }

    private func buildTable() {
        tableView.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.table(for: paneID))
        tableView.delegate = self
        tableView.dataSource = self
        tableView.actionDelegate = self
        tableView.registerForDraggedTypes([.fileURL, .pulseFilesInternalDrag])
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 34
        tableView.doubleAction = #selector(openDoubleClickedItem)
        tableView.target = self
        tableView.headerView = NSTableHeaderView()
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        dualPaneGridStyleMask = tableView.gridStyleMask

        addColumn(identifier: ColumnID.name, title: "Name", width: Self.columnMetrics[ColumnID.name]?.compactWidth ?? 360)
        addColumn(identifier: ColumnID.kind, title: "Kind", width: Self.columnMetrics[ColumnID.kind]?.compactWidth ?? 140)
        addColumn(identifier: ColumnID.size, title: "Size", width: Self.columnMetrics[ColumnID.size]?.compactWidth ?? 90)
        addColumn(identifier: ColumnID.modified, title: "Modified", width: Self.columnMetrics[ColumnID.modified]?.compactWidth ?? 170)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = identifier == ColumnID.name ? 180 : 70
        column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        tableView.addTableColumn(column)
    }

    private func applyColumnLayout(force: Bool = false) {
        guard tableView.tableColumns.count == 4 else { return }
        let availableWidth = scrollView.contentView.bounds.width - 1
        guard availableWidth > 0 else { return }
        guard force || abs(availableWidth - lastAppliedColumnLayoutWidth) > 8 else { return }
        lastAppliedColumnLayoutWidth = availableWidth

        if hasOppositePane {
            scrollView.hasHorizontalScroller = true
            tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
            tableView.gridStyleMask = dualPaneGridStyleMask
            setColumnWidths(Self.columnMetrics.mapValues(\.compactWidth))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        scrollView.hasHorizontalScroller = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.gridStyleMask = []
        let targetWidth = max(availableWidth - 2, 0)
        let minimumWidths = Self.columnMetrics.mapValues(\.singlePaneMinimumWidth)
        let minimumTotal = minimumWidths.values.reduce(CGFloat(0), +)
        guard targetWidth > minimumTotal else {
            setColumnWidths(fittedMinimumWidths(minimumWidths, targetWidth: targetWidth))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        setColumnWidths(Self.columnMetrics.mapValues { metrics in
            max(metrics.singlePaneMinimumWidth, floor(targetWidth * metrics.singlePaneWeight))
        })
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func fittedMinimumWidths(_ widths: [String: CGFloat], targetWidth: CGFloat) -> [String: CGFloat] {
        let minimumTotal = widths.values.reduce(CGFloat(0), +)
        guard minimumTotal > targetWidth, targetWidth > 0 else { return widths }
        let scale = targetWidth / minimumTotal
        return widths.mapValues { max(70, floor($0 * scale)) }
    }

    private func setColumnWidths(_ widths: [String: CGFloat]) {
        for column in tableView.tableColumns {
            guard let width = widths[column.identifier.rawValue] else { continue }
            if abs(column.width - width) > 1 {
                column.width = width
            }
        }
    }

    private func buildLayout() {
        [header, scrollView, contentOverlay, statusView, activeStripe].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        activeStripe.wantsLayer = true
        activeStripe.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.activeIndicator(for: paneID))
        let headerStack = NSStackView(views: [directoryIcon, breadcrumb, hiddenButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerStack)

        NSLayoutConstraint.activate([
            activeStripe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activeStripe.topAnchor.constraint(equalTo: view.topAnchor),
            activeStripe.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activeStripe.widthAnchor.constraint(equalToConstant: 3),

            header.leadingAnchor.constraint(equalTo: activeStripe.trailingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 42),

            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            headerStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            directoryIcon.widthAnchor.constraint(equalToConstant: 20),
            directoryIcon.heightAnchor.constraint(equalToConstant: 20),

            scrollView.leadingAnchor.constraint(equalTo: activeStripe.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusView.topAnchor),

            contentOverlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentOverlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentOverlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            statusView.leadingAnchor.constraint(equalTo: activeStripe.trailingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func bindViewModel() {
        viewModel.onChange = { [weak self] in self?.reloadData() }
        viewModel.onDirectoryChanged = { [weak self] url in self?.onDirectoryChanged?(url) }
        viewModel.onDisplayPreferencesChanged = { [weak self] showsHiddenFiles, sort in
            self?.onDisplayPreferencesChanged?(showsHiddenFiles, sort)
        }
        reloadData()
    }

    private func item(forRow row: Int) -> FileItem? {
        let index = row - realRowOffset
        guard viewModel.visibleItems.indices.contains(index) else { return nil }
        return viewModel.visibleItems[index]
    }

    private func row(for item: FileItem) -> Int? {
        guard let index = viewModel.visibleItems.firstIndex(where: { isSameFileURL($0.url, item.url) }) else { return nil }
        return index + realRowOffset
    }

    private func isParentRow(_ row: Int) -> Bool {
        canShowParentRow && row == 0
    }

    private func defaultFocusRow() -> Int? {
        if !viewModel.visibleItems.isEmpty {
            return realRowOffset
        }
        if canShowParentRow {
            return 0
        }
        return nil
    }

    private func selectDefaultRow() {
        guard let row = defaultFocusRow(), row >= 0, row < tableView.numberOfRows else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func refreshAppearance() {
        header.material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        LiquidGlassStyle.applyButtonChrome(to: hiddenButton)
        LiquidGlassStyle.applyPanelChrome(to: view)
        updatePaneChrome()
        requestTableReload()
    }

    private func reloadData() {
        requestTableReload()
    }

    /// Keeps AppKit's field editor alive while the table's backing listing is
    /// changing. This is deliberately a defer/coalesce policy: the current
    /// rename is completed or cancelled before the table is rebuilt.
    private func requestTableReload() {
        guard let editedItem = inlineRenameItem,
              inlineRenameSession.isEditing else {
            performTableReload()
            return
        }

        // A filtered-out item is still a valid rename target. Only cancel when
        // the file itself has disappeared, so we never submit a stale path.
        switch InlineRenameReloadPolicy.decision(
            isEditing: inlineRenameSession.isEditing,
            itemExists: FileManager.default.fileExists(atPath: editedItem.url.path)
        ) {
        case .deferReload:
            hasDeferredTableReload = true
        case .cancelRenameAndReload:
            inlineRenameSession.cancel()
            clearInlineRenameState()
            hasDeferredTableReload = false
            performTableReload()
            showInlineRenameItemRemovedAlert()
        case .reloadNow:
            performTableReload()
        }
    }

    private func performTableReload() {
        isReloadingData = true
        defer { isReloadingData = false }
        breadcrumb.configure(url: viewModel.currentDirectory)
        directoryIcon.image = FileIconProvider.shared.image(for: FileIconKey(fileType: .folder, fileExtension: ""))
        tableView.reloadData()
        pruneInvalidSelection()
        restorePreviousSelectionIfPossible()
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        if !selectPendingItemIfAvailable(), tableView.selectedRow == -1, tableView.numberOfRows > 0 {
            selectDefaultRow()
        }
        previousSelectionURLs = selectedItems.map(\.url)
        configureStatusView()
        configureContentOverlay()
        onSelectionChanged?(selectedItems)
        let hiddenSymbol = viewModel.showsHiddenFiles ? "eye" : "eye.slash"
        hiddenButton.image = NSImage(systemSymbolName: hiddenSymbol, accessibilityDescription: "Toggle Hidden Files".localized)
    }

    private func flushDeferredTableReloadIfNeeded() {
        guard hasDeferredTableReload else { return }
        hasDeferredTableReload = false
        performTableReload()
    }

    private func showInlineRenameItemRemovedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Cancelled".localized
        alert.informativeText = "The item being renamed was removed or moved by another application. No rename was made.".localized
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @discardableResult
    private func selectPendingItemIfAvailable() -> Bool {
        guard !viewModel.isLoading, let pendingSelectionURL else { return false }
        let selectedURL = pendingSelectionURL
        guard let itemIndex = viewModel.visibleItems.firstIndex(where: {
            isSameFileURL($0.url, pendingSelectionURL)
        }) else { return false }
        let row = itemIndex + realRowOffset
        guard row >= 0, row < tableView.numberOfRows else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        self.pendingSelectionURL = nil
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        previousSelectionURLs = [selectedURL]
        return true
    }

    private func isSameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private func selectFilenameStem(for item: FileItem) {
        guard !item.isDirectory,
              !item.url.pathExtension.isEmpty,
              let editor = view.window?.fieldEditor(false, for: tableView) else { return }
        let stem = (item.filename as NSString).deletingPathExtension
        guard !stem.isEmpty else { return }
        editor.selectedRange = NSRange(location: 0, length: stem.count)
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func isDimmed(_ item: FileItem) -> Bool {
        dimmedFileURLs.contains(normalizedPath(item.url))
    }

    private func restorePreviousSelectionIfPossible() {
        guard pendingSelectionURL == nil, !previousSelectionURLs.isEmpty else { return }

        let rows = previousSelectionURLs.reduce(into: IndexSet()) { partialResult, url in
            if let index = viewModel.visibleItems.firstIndex(where: { isSameFileURL($0.url, url) }) {
                partialResult.insert(index + realRowOffset)
            }
        }
        guard !rows.isEmpty else { return }
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    private func configureStatusView() {
        volumeStatusCache.resolveIfNeeded(
            for: viewModel.currentDirectory,
            loadGeneration: viewModel.loadGeneration
        )
        let actions = recoveryActions()
        statusView.configure(
            items: viewModel.visibleItems,
            selectedItems: selectedItems,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            partialRefreshFailure: viewModel.partialRefreshFailure,
            isPartialRefreshRetryScheduled: viewModel.isPartialRefreshRetryScheduled,
            volumeStatus: volumeStatusCache.status,
            actions: actions
        )
    }

    private func configureContentOverlay() {
        contentOverlay.configure(
            paneID: paneID,
            isLoading: viewModel.isLoading,
            visibleItems: viewModel.visibleItems,
            errorMessage: viewModel.errorMessage,
            actions: recoveryActions()
        )
    }

    private func recoveryActions() -> [PaneStatusView.Action] {
        guard let loadFailure = viewModel.loadFailure, !viewModel.isLoading else { return [] }
        if loadFailure.isOutsideSandbox {
            return [
                PaneStatusView.Action(
                    title: "Open Sandbox".localized,
                    accessibilityLabel: "Open experimental sandbox root".localized,
                    handler: { [weak self] in self?.viewModel.navigateToSandboxRoot() }
                )
            ]
        }
        if loadFailure.isMissingDirectory {
            return [
                PaneStatusView.Action(
                    title: "Back".localized,
                    accessibilityLabel: "Go back to the previous folder".localized,
                    handler: { [weak self] in self?.viewModel.goBack() }
                ),
                PaneStatusView.Action(
                    title: "Parent".localized,
                    accessibilityLabel: "Open the missing folder’s parent".localized,
                    handler: { [weak self] in self?.viewModel.navigateToParentOfFailedDirectory() }
                ),
                PaneStatusView.Action(
                    title: "Choose…".localized,
                    accessibilityLabel: "Choose another folder".localized,
                    handler: { [weak self] in self?.chooseRecoveryDirectory() }
                )
            ]
        }
        if loadFailure.isRetryable {
            return [
                PaneStatusView.Action(
                    title: "Retry".localized,
                    accessibilityLabel: "Retry loading this folder".localized,
                    handler: { [weak self] in self?.viewModel.retryFailedDirectoryLoad() }
                )
            ]
        }
        return []
    }

    private func chooseRecoveryDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose".localized
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let url = panel?.url else { return }
            self.openGrantedRecoveryDirectory(url)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func openGrantedRecoveryDirectory(_ url: URL) {
        do {
            let accessibleURL = try grantedDirectoryURL(for: url)
            onDirectoryAccessGranted?(accessibleURL)
            navigate(to: accessibleURL)
        } catch {
            showDirectoryAccessDeniedAlert()
        }
    }

    private func grantedDirectoryURL(for url: URL) throws -> URL {
        if accessGrantService.hasGrant(containing: url) {
            try viewModel.validateAccess(to: url)
            return url
        }

        if viewModel.isAccessRestrictedToExperimentalSandbox {
            try viewModel.validateAccess(to: url)
            return url
        }

        let grant = try accessGrantService.grantAccess(to: url)
        try viewModel.validateAccess(to: grant.url)
        return grant.url
    }

    private func showDirectoryAccessDeniedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Folder Access Needed".localized
        alert.informativeText = "PulseFiles does not currently have permission to access this folder. Choose another folder or grant access in macOS privacy settings.".localized
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func refresh() {
        viewModel.loadCurrentDirectory()
    }

    @objc private func toggleHidden() {
        toggleHiddenFiles()
    }

    @objc private func openDoubleClickedItem() {
        openFocusedItem()
    }
}

extension FilePaneViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.visibleItems.count + realRowOffset
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = FileTableRowView()
        rowView.drawsActiveSelection = isPaneActive
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue else { return nil }
        if isParentRow(row) {
            return parentCell(for: identifier)
        }
        guard let item = item(forRow: row) else { return nil }
        let cell = NSTableCellView()
        cell.alphaValue = isDimmed(item) ? 0.45 : 1
        let text: NSTextField
        if identifier == "name" {
            let renameTextField = InlineRenameTextField(string: item.filename)
            renameTextField.itemURL = item.url
            renameTextField.sessionGeneration = inlineRenameSession.generation(for: item.url)
            renameTextField.delegate = self
            renameTextField.target = self
            renameTextField.action = #selector(commitInlineRenameFromAction(_:))
            text = renameTextField
        } else {
            text = NSTextField(labelWithString: string(for: item, column: identifier))
        }
        text.isEditable = identifier == "name"
        text.isBordered = false
        text.drawsBackground = false
        text.lineBreakMode = .byTruncatingMiddle
        if identifier == "name" {
            text.textColor = FileTypeColorPalette.textColor(
                for: item,
                isSelected: tableView.isRowSelected(row),
                isActivePane: isPaneActive,
                appearance: view.effectiveAppearance
            )
        } else {
            text.textColor = LiquidGlassStyle.label
        }
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)

        if identifier == "name" {
            let imageView = NSImageView(image: FileIconProvider.shared.image(for: item.iconKey))
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.imageView = imageView
        } else {
            text.alignment = identifier == "size" ? .right : .left
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        reloadRowsForSelectionColorChange()
        configureStatusView()
        configureContentOverlay()
        onSelectionChanged?(selectedItems)
        if !isReloadingData {
            previousSelectionURLs = selectedItems.map(\.url)
        }
        if !isReloadingData {
            onActivate?()
        }
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        switch tableColumn.identifier.rawValue {
        case "kind":
            setSort(.kind)
        case "size":
            setSort(.size)
        case "modified":
            setSort(.modified)
        default:
            setSort(.name)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if !isReloadingData {
            onActivate?()
        }
        return true
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        tableColumn?.identifier.rawValue == "name"
            && inlineRenameRow == row
            && item(forRow: row) != nil
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier.rawValue == "name",
              let item = item(forRow: row),
              let proposedName = object as? String,
              let generation = inlineRenameSession.generation(for: item.url) else { return }
        commitInlineRename(itemURL: item.url, sessionGeneration: generation, proposedName: proposedName, isCancelled: false)
    }

    @objc private func commitInlineRenameFromAction(_ sender: NSTextField) {
        guard let sender = sender as? InlineRenameTextField else { return }
        commitInlineRename(
            itemURL: sender.itemURL,
            sessionGeneration: sender.sessionGeneration,
            proposedName: sender.stringValue,
            isCancelled: false
        )
    }

    /// The sole submission path for an inline rename session. AppKit can send
    /// an action, end-editing notification, and object value for one edit.
    private func commitInlineRename(itemURL: URL?, sessionGeneration: UInt?, proposedName: String, isCancelled: Bool) {
        guard let itemURL,
              let sessionGeneration,
              inlineRenameSession.matches(itemURL: itemURL, generation: sessionGeneration) else { return }

        let item = inlineRenameItem
        guard isCancelled || (item.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false) else {
            inlineRenameSession.cancel()
            clearInlineRenameState()
            showInlineRenameItemRemovedAlert()
            flushDeferredTableReloadIfNeeded()
            return
        }
        let result = inlineRenameSession.commit(
            itemURL: itemURL,
            generation: sessionGeneration,
            proposedName: proposedName,
            originalName: item?.filename,
            isCancelled: isCancelled
        )
        clearInlineRenameState()
        if case let .rename(_, name) = result, let item {
            onRenameItem?(item, name)
        }
        flushDeferredTableReloadIfNeeded()
    }

    private func item(for url: URL) -> FileItem? {
        viewModel.visibleItems.first { isSameFileURL($0.url, url) }
    }

    private func updateInlineRenameField(at row: Int, for itemURL: URL) {
        guard let column = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }),
              let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cell.textField as? InlineRenameTextField else { return }
        textField.itemURL = itemURL
        textField.sessionGeneration = inlineRenameSession.generation(for: itemURL)
    }

    private func clearInlineRenameState() {
        inlineRenameRow = nil
        inlineRenameItem = nil
    }

    private func reloadRowsForSelectionColorChange() {
        let currentSelectedRowIndexes = tableView.selectedRowIndexes
        let changedRows = IndexSet(
            previousSelectedRowIndexes.filter { !currentSelectedRowIndexes.contains($0) }
                + currentSelectedRowIndexes.filter { !previousSelectedRowIndexes.contains($0) }
        )
        previousSelectedRowIndexes = currentSelectedRowIndexes
        guard !changedRows.isEmpty else { return }
        guard !inlineRenameSession.isEditing else {
            hasDeferredTableReload = true
            return
        }
        tableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    private func pruneInvalidSelection() {
        guard tableView.numberOfRows > 0 else {
            tableView.deselectAll(nil)
            return
        }
        let validRows = IndexSet(tableView.selectedRowIndexes.filter { row in
            row >= 0 && row < tableView.numberOfRows
        })
        if validRows != tableView.selectedRowIndexes {
            tableView.selectRowIndexes(validRows, byExtendingSelection: false)
        }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let item = item(forRow: row) else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        pasteboardItem.setString("PulseFiles", forType: .pulseFilesInternalDrag)
        return pasteboardItem
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let destination = dropDestination(forRow: row, operation: dropOperation) else { return [] }
        let urls = draggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        let operation = resolvedDropOperation(for: urls, destination: destination, pasteboard: info.draggingPasteboard)
        guard canDrop(urls, into: destination, operation: operation) else { return [] }
        return operation == .copy ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let destination = dropDestination(forRow: row, operation: dropOperation) else { return false }
        let urls = draggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let operation = resolvedDropOperation(for: urls, destination: destination, pasteboard: info.draggingPasteboard)
        guard canDrop(urls, into: destination, operation: operation) else { return false }
        onDropURLs?(urls, destination, operation == .copy)
        return true
    }

    private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { object -> URL? in
                if let url = object as? URL { return url }
                return (object as? NSURL)?.absoluteURL
            } ?? []
    }

    private func resolvedDropOperation(for urls: [URL], destination: URL, pasteboard: NSPasteboard) -> DropTransferPolicy.Operation {
        dropTransferPolicy.resolvedOperation(
            for: urls,
            destinationDirectory: destination,
            isInternalAppDrag: pasteboard.string(forType: .pulseFilesInternalDrag) != nil,
            optionForcesCopy: NSApp.currentEvent?.modifierFlags.contains(.option) == true
        )
    }

    private func canDrop(_ urls: [URL], into destination: URL, operation: DropTransferPolicy.Operation) -> Bool {
        // NSTableView asks this synchronously on the main thread. Start probes,
        // then wait for a later validation callback rather than blocking on a
        // slow or disappearing volume.
        dropProbeCache.requestDirectory(destination)
        urls.forEach { dropProbeCache.requestDirectory($0) }
        guard dropProbeCache.directoryValue(for: destination) == true else { return false }
        guard urls.allSatisfy({ dropProbeCache.directoryValue(for: $0) != nil }) else { return false }
        guard !isDroppingInsideDraggedDirectory(urls, destination: destination) else { return false }
        guard operation == .copy || !isSameDirectoryMove(urls, destination: destination) else { return false }
        return true
    }

    private func isSameDirectoryMove(_ urls: [URL], destination: URL) -> Bool {
        urls.allSatisfy {
            FilePathComparison.isSamePath($0.deletingLastPathComponent(), destination)
        }
    }

    private func isDroppingInsideDraggedDirectory(_ urls: [URL], destination: URL) -> Bool {
        urls.contains { source in
            guard isDirectory(source) else { return false }
            return FilePathComparison.isSameOrDescendant(destination, ofDirectory: source)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        dropProbeCache.requestDirectory(url)
        return dropProbeCache.directoryValue(for: url) == true
    }

    private func dropDestination(forRow row: Int, operation: NSTableView.DropOperation) -> URL? {
        guard !isParentRow(row) else { return nil }
        if operation == .on, let item = item(forRow: row), item.isDirectory {
            return item.url
        }
        return currentDirectory
    }

    private func parentCell(for identifier: String) -> NSView {
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: identifier == "name" ? ".." : "--")
        text.textColor = LiquidGlassStyle.secondaryLabel
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        if identifier == "name" {
            let imageView = NSImageView(image: NSImage(systemSymbolName: "arrow.up.folder", accessibilityDescription: "Parent Folder".localized) ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField = text
        return cell
    }


    static func sizeDisplayString(for item: FileItem) -> String {
        item.isDirectory && !item.isSymbolicLink ? "--" : FileSizeFormatter.string(fromByteCount: item.size)
    }

    private func string(for item: FileItem, column: String) -> String {
        switch column {
        case "name":
            return item.displayName
        case "size":
            return Self.sizeDisplayString(for: item)
        case "kind":
            return item.typeDescription
        case "modified":
            return item.modificationDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        default:
            return ""
        }
    }
}

extension FilePaneViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? InlineRenameTextField else { return }
        let movement = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        commitInlineRename(
            itemURL: textField.itemURL,
            sessionGeneration: textField.sessionGeneration,
            proposedName: textField.stringValue,
            isCancelled: movement == NSCancelTextMovement
        )
    }
}

private final class InlineRenameTextField: NSTextField {
    var itemURL: URL?
    var sessionGeneration: UInt?
}

/// Defines the safe table-refresh behavior while AppKit owns an inline editor.
enum InlineRenameReloadPolicy {
    enum Decision: Equatable {
        case reloadNow
        case deferReload
        case cancelRenameAndReload
    }

    static func decision(isEditing: Bool, itemExists: Bool) -> Decision {
        guard isEditing else { return .reloadNow }
        return itemExists ? .deferReload : .cancelRenameAndReload
    }
}

/// Tracks one edit independently from the table's lifecycle callbacks.
/// A successful, unchanged, or cancelled decision consumes the session; stale
/// callbacks therefore cannot submit a rename for a newer edit.
struct InlineRenameCommitSession {
    enum Result: Equatable {
        case rename(URL, String)
        case noChange
        case cancelled
        case ignored
    }

    private(set) var itemURL: URL?
    /// Identity is a normalized path, rather than the table row which can
    /// change under sorting, filtering, or a directory monitor notification.
    private(set) var normalizedItemPath: String?
    private(set) var generation: UInt = 0

    var isEditing: Bool { itemURL != nil }

    mutating func begin(for itemURL: URL) {
        generation &+= 1
        self.itemURL = itemURL
        normalizedItemPath = normalizedPath(for: itemURL)
    }

    func generation(for itemURL: URL) -> UInt? {
        matches(itemURL: itemURL, generation: generation) ? generation : nil
    }

    func matches(itemURL: URL, generation: UInt) -> Bool {
        guard normalizedItemPath != nil else { return false }
        return self.generation == generation && self.normalizedItemPath == normalizedPath(for: itemURL)
    }

    mutating func commit(itemURL: URL, generation: UInt, proposedName: String, originalName: String?, isCancelled: Bool) -> Result {
        guard matches(itemURL: itemURL, generation: generation) else { return .ignored }
        defer { cancel() }
        guard !isCancelled else { return .cancelled }
        guard let originalName else { return .cancelled }
        guard proposedName != originalName else { return .noChange }
        return .rename(itemURL, proposedName)
    }

    mutating func cancel() {
        itemURL = nil
        normalizedItemPath = nil
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

extension FilePaneViewController: FileTableViewActionDelegate {
    func fileTableViewDidActivate(_ tableView: FileTableView) {
        onActivate?()
    }

    func fileTableViewDidRequestOpen(_ tableView: FileTableView) {
        openFocusedItem()
    }

    func fileTableViewDidRequestQuickLook(_ tableView: FileTableView) {
        onCommand?(.quickLook)
    }

    func fileTableViewDidRequestParent(_ tableView: FileTableView) {
        onCommand?(.parent)
    }

    func fileTableViewDidRequestBack(_ tableView: FileTableView) {
        onCommand?(.back)
    }

    func fileTableViewDidRequestForward(_ tableView: FileTableView) {
        onCommand?(.forward)
    }

    func fileTableView(_ tableView: FileTableView, didRequestLocation url: URL) {
        navigate(to: url)
    }

    func fileTableViewDidRequestToggleHidden(_ tableView: FileTableView) {
        onCommand?(.toggleHiddenFiles)
    }

    func fileTableViewDidRequestTerminalToggle(_ tableView: FileTableView) {
        onCommand?(.toggleTerminal)
    }

    func fileTableViewDidRequestNewFolder(_ tableView: FileTableView) {
        onCommand?(.newFolder)
    }

    func fileTableViewDidRequestNewFile(_ tableView: FileTableView) {
        onCommand?(.newFile)
    }

    func fileTableViewDidRequestPaneSwitch(_ tableView: FileTableView) {
        onCommand?(.switchPane)
    }

    func fileTableView(_ tableView: FileTableView, contextMenuForRow row: Int) -> NSMenu? {
        if row >= 0, !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let menu = NSMenu(title: "File")
        if isParentRow(row) {
            menu.addItem(contextMenuItem("Open Parent Folder".localized, action: #selector(contextOpenParent)))
            return menu
        }

        if let rowItem = item(forRow: row) {
            menu.addItem(contextMenuItem("Open", action: #selector(contextOpen)))
            if !rowItem.isDirectory {
                menu.addItem(contextMenuItem("Open With…".localized, action: #selector(contextOpenWith)))
                menu.addItem(openWithMenu(for: rowItem.url))
            }
            menu.addItem(contextMenuItem("Rename", action: #selector(contextRename)))
            menu.addItem(contextMenuItem("Duplicate", action: #selector(contextDuplicate)))
            menu.addItem(contextMenuItem("Get Info", action: #selector(contextGetInfo)))
            if hasOppositePane {
                menu.addItem(.separator())
                menu.addItem(contextMenuItem("Copy to Opposite Pane", action: #selector(contextCopy)))
                menu.addItem(contextMenuItem("Move to Opposite Pane", action: #selector(contextMove)))
            }
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("Copy Path", action: #selector(contextCopyPath)))
            menu.addItem(contextMenuItem("Reveal in Finder", action: #selector(contextReveal)))
            menu.addItem(contextMenuItem("Delete", action: #selector(contextTrash)))
        } else {
            menu.addItem(contextMenuItem("New File", action: #selector(contextNewFile)))
            menu.addItem(contextMenuItem("New Folder", action: #selector(contextNewFolder)))
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("Refresh", action: #selector(contextRefresh)))
            menu.addItem(contextMenuItem("Select All", action: #selector(contextSelectAll)))
            menu.addItem(contextMenuItem("Invert Selection", action: #selector(contextInvertSelection)))
            menu.addItem(contextMenuItem(viewModel.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files", action: #selector(contextToggleHidden)))
        }
        return menu
    }

    private func contextMenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.setAccessibilityLabel(title)
        return item
    }

    private func openWithMenu(for url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open With")

        let defaultItem = NSMenuItem(title: "Default Application", action: #selector(contextOpenWithDefault(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = url
        submenu.addItem(defaultItem)

        let loadingItem = NSMenuItem(title: "Loading Applications…", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        submenu.addItem(loadingItem)

        item.submenu = submenu
        openWithApplicationResolver.resolveApplications(
            for: url,
            menuItem: item,
            submenu: submenu,
            loadingItem: loadingItem
        ) { [weak self] applicationURL in
            let applicationItem = NSMenuItem(title: applicationURL.deletingPathExtension().lastPathComponent, action: #selector(Self.contextOpenWithApplication(_:)), keyEquivalent: "")
            applicationItem.target = self
            applicationItem.representedObject = OpenWithRequest(fileURL: url, applicationURL: applicationURL)
            return applicationItem
        }
        return item
    }

    @objc private func contextOpenParent() { onCommand?(.parent) }
    @objc private func contextOpen() { onCommand?(.open) }
    @objc private func contextOpenWith() { onCommand?(.openWith) }
    @objc private func contextRename() { onCommand?(.rename) }
    @objc private func contextDuplicate() { onCommand?(.duplicate) }
    @objc private func contextGetInfo() { onCommand?(.getInfo) }
    @objc private func contextCopy() { onCommand?(.copy) }
    @objc private func contextMove() { onCommand?(.move) }
    @objc private func contextTrash() { onCommand?(.trash) }
    @objc private func contextNewFile() { onCommand?(.newFile) }
    @objc private func contextNewFolder() { onCommand?(.newFolder) }
    @objc private func contextRefresh() { onCommand?(.refresh) }
    @objc private func contextSelectAll() { onCommand?(.selectAll) }
    @objc private func contextInvertSelection() { onCommand?(.invertSelection) }
    @objc private func contextReveal() { onCommand?(.reveal) }
    @objc private func contextToggleHidden() { onCommand?(.toggleHiddenFiles) }
    @objc private func contextOpenWithDefault(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenWithApplication?(url, nil)
    }

    @objc private func contextOpenWithApplication(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? OpenWithRequest else { return }
        onOpenWithApplication?(request.fileURL, request.applicationURL)
    }

    @objc private func contextCopyPath() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
}

private final class OpenWithRequest {
    let fileURL: URL
    let applicationURL: URL

    init(fileURL: URL, applicationURL: URL) {
        self.fileURL = fileURL
        self.applicationURL = applicationURL
    }
}

private final class PaneContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

extension NSPasteboard.PasteboardType {
    static let pulseFilesInternalDrag = NSPasteboard.PasteboardType("com.pulsefiles.internal-drag")
}

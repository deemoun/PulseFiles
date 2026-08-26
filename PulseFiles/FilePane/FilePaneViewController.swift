// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

package final class FilePaneViewController: NSViewController {
    package let tableAdapter = FilePaneTableAdapter()

    package let paneID: PaneID
    package let viewModel: FilePaneViewModel
    package let tableView = FileTableView()
    package let keyboardNavigationController = PaneKeyboardNavigationController()
    package let contextMenuProvider: FilePaneContextMenuProvider

    package weak var navigationDelegate: FilePaneNavigationDelegate?
    package weak var commandDelegate: FilePaneCommandDelegate?
    package weak var presentationDelegate: FilePanePresentationDelegate?

    package let header = NSVisualEffectView()
    package let breadcrumb = BreadcrumbView()
    package let directoryIcon = NSImageView()
    package let hiddenButton = NSButton()
    package let presentationSelector = NSSegmentedControl()
    package let tabSelector = NSSegmentedControl()
    package let scrollView = NSScrollView()
    package let contentOverlay = PaneContentOverlayView()
    package let statusView = PaneStatusView()
    package let activeStripe = NSView()
    package var isReloadingData = false
    package var isPaneActive = false
    package var dimmedFileURLs = Set<String>()
    package var previousSelectedRowIndexes = IndexSet()
    package var previousSelectionURLs: [URL] = []
    /// URLs survive sorting, filtering, and monitor-driven reloads; row indexes do not.
    package var selectionRestoration = FilePaneSelectionRestoration()
    package var quickSearchState = QuickSearchState()
    package var inlineRenameRow: Int?
    /// The item snapshot remains valid while a refresh is deferred, even when
    /// filtering, sorting, or navigation has already changed the view model.
    package var inlineRenameItem: FileItem?
    package var inlineRenameSession = InlineRenameCommitSession()
    package let inlineRenameCoordinator = InlineRenameCoordinator()
    package var hasDeferredTableReload = false
    package var hasOppositePane = true
    /// Single-pane tables have room to breathe, so keep metadata away from column dividers.
    /// Compact dual-pane tables retain their tighter spacing to preserve useful width.
    package var metadataColumnContentInset: CGFloat { hasOppositePane ? 6 : 14 }
    package lazy var dropProbeCache = FileSystemProbeCache()
    package lazy var dropCoordinator = FilePaneDropCoordinator(transferPolicy: DropTransferPolicy(volumeIdentifierProvider: { [weak self] url in
        guard let self else { return nil }
        self.dropProbeCache.requestVolumeIdentifier(url)
        return self.dropProbeCache.volumeIdentifier(for: url)
    }))
    private let authorizedFolderSelection: AuthorizedFolderSelecting
    package lazy var volumeStatusCache = VolumeStatusResolutionCache(directory: viewModel.currentDirectory)
    package let thumbnailLoader: any ThumbnailLoading
    package let thumbnailRequests = ThumbnailRequestCoordinator()
    private(set) var presentationMode: PanePresentationMode
    private var liquidGlassStyle: LiquidGlassStyle

    package init(
        paneID: PaneID,
        viewModel: FilePaneViewModel,
        presentationMode: PanePresentationMode = .list,
        thumbnailLoader: any ThumbnailLoading,
        openWithApplicationResolver: OpenWithMenuApplicationResolver? = nil,
        authorizedFolderSelection: AuthorizedFolderSelecting,
        liquidGlassStyle: LiquidGlassStyle
    ) {
        self.paneID = paneID
        self.viewModel = viewModel
        self.presentationMode = presentationMode
        self.thumbnailLoader = thumbnailLoader
        self.contextMenuProvider = FilePaneContextMenuProvider(openWithApplicationResolver: openWithApplicationResolver ?? OpenWithMenuApplicationResolver())
        self.authorizedFolderSelection = authorizedFolderSelection
        self.liquidGlassStyle = liquidGlassStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    package var currentDirectory: URL { viewModel.currentDirectory }
    package var sortDescriptor: FileSortDescriptor { viewModel.sortDescriptor }
    package var showsHiddenFiles: Bool { viewModel.showsHiddenFiles }
    package var selectedItems: [FileItem] {
        tableView.selectedRowIndexes.compactMap { item(forRow: $0) }
    }

    package var focusedItem: FileItem? {
        viewModel.focusedURL.flatMap(item(for:))
    }

    package var syntheticFocusedDestination: PaneFocusDestination?

    package var focusedDestination: PaneFocusDestination? {
        if syntheticFocusedDestination == .parent, canShowParentRow { return .parent }
        return viewModel.focusedURL.map(PaneFocusDestination.item)
    }

    package var displayedDestinations: [PaneFocusDestination] {
        (canShowParentRow ? [.parent] : []) + viewModel.visibleItems.map { .item($0.url) }
    }

    package func setFocusedURL(_ url: URL?) {
        setFocusedDestination(url.map(PaneFocusDestination.item))
    }

    package func setFocusedDestination(_ destination: PaneFocusDestination?) {
        let oldRow = row(for: focusedDestination)
        syntheticFocusedDestination = destination == .parent ? .parent : nil
        switch destination {
        case let .item(url): viewModel.setFocusedURL(url)
        case .parent, nil: viewModel.setFocusedURL(nil)
        }
        let newRow = row(for: focusedDestination)
        updateKeyboardFocusIndicator(at: oldRow, isFocused: false)
        updateKeyboardFocusIndicator(at: newRow, isFocused: true)
        let rows = IndexSet([oldRow, newRow].compactMap { $0 })
        guard !rows.isEmpty, tableView.numberOfColumns > 0 else { return }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        // Reloading cells does not guarantee that AppKit recreates the row
        // view. Reapply the indicator after the reload so a reused row cannot
        // make keyboard focus movement appear to do nothing.
        updateKeyboardFocusIndicator(at: oldRow, isFocused: false)
        updateKeyboardFocusIndicator(at: newRow, isFocused: true)
    }

    private func updateKeyboardFocusIndicator(at row: Int?, isFocused: Bool) {
        guard let row,
              row >= 0,
              row < tableView.numberOfRows,
              let rowView = tableView.rowView(atRow: row, makeIfNecessary: true) as? FileTableRowView else { return }
        rowView.drawsKeyboardFocus = isFocused
        rowView.needsDisplay = true
    }

    package var parentURL: URL {
        viewModel.currentDirectory.deletingLastPathComponent()
    }

    package var canNavigateToParent: Bool {
        parentURL != viewModel.currentDirectory && viewModel.canNavigate(to: parentURL)
    }

    package var canShowParentRow: Bool {
        viewModel.searchQuery.isEmpty && canNavigateToParent
    }

    package var realRowOffset: Int { canShowParentRow ? 1 : 0 }

    package override func loadView() {
        let paneView = PaneContainerView()
        paneView.onMouseDown = { [weak self] in self.map { $0.navigationDelegate?.filePane($0, didEmit: .activate) } }
        view = paneView
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.container(for: paneID))
        liquidGlassStyle.applyPanelChrome(to: view)
    }

    package override func viewDidLoad() {
        super.viewDidLoad()
        volumeStatusCache.onChange = { [weak self] in self?.configureStatusView() }
        contextMenuProvider.onCommand = { [weak self] command in self.map { $0.commandDelegate?.filePane($0, didEmit: .command(command)) } }
        contextMenuProvider.onOpenWithApplication = { [weak self] file, app in self.map { $0.commandDelegate?.filePane($0, didEmit: .openWith(file, app)) } }
        inlineRenameCoordinator.onCommit = { [weak self] url, generation, name, cancelled in
            self?.commitInlineRename(itemURL: url, sessionGeneration: generation, proposedName: name, isCancelled: cancelled)
        }
        buildHeader()
        buildTable()
        buildLayout()
        bindViewModel()
        let initialMode = presentationMode
        presentationMode = .list
        setPresentationMode(initialMode, notify: false)
    }

    package override func viewDidLayout() {
        super.viewDidLayout()
        tableAdapter.applyLayout(hasOppositePane: hasOppositePane)
    }

    package func loadDirectory(selecting url: URL? = nil, onLoaded: (() -> Void)? = nil) {
        selectionRestoration.prepare(url)
        viewModel.loadCurrentDirectory { [weak self] in
            self?.selectPendingItemIfAvailable()
            onLoaded?()
        }
    }

    package func selectItem(at url: URL) {
        selectionRestoration.prepare(url)
        if !viewModel.isLoading {
            selectPendingItemIfAvailable()
        }
    }

    package func logicalStateSnapshot() -> PaneState {
        viewModel.logicalStateSnapshot()
    }

    package func restoreLogicalState(_ snapshot: PaneState) throws {
        preparePendingSelection(snapshot.focusedURL)
        try viewModel.restoreLogicalState(snapshot) { [weak self] in
            self?.selectPendingItemIfAvailable()
        }
    }

    package func newTab() { viewModel.newTab() }
    @discardableResult func closeTab() -> Bool { viewModel.closeTab() }
    package func nextTab() { viewModel.selectNextTab() }
    package func previousTab() { viewModel.selectPreviousTab() }
    package func selectTab(id: UUID) { viewModel.selectTab(id: id) }
    @discardableResult func reorderTab(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        viewModel.reorderTab(from: sourceIndex, to: destinationIndex)
    }

    package func preparePendingSelection(_ url: URL?) {
        selectionRestoration.prepare(url)
        if let url { setFocusedURL(url) }
    }

    /// Selection commands intentionally operate only on real file rows; the
    /// synthetic parent row is navigation, not a filesystem item.
    package func selectAllItems() {
        let rows = IndexSet(integersIn: realRowOffset..<tableView.numberOfRows)
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    package func deselectAllItems() {
        let focusedURL = viewModel.focusedURL
        tableView.deselectAll(nil)
        viewModel.setFocusedURL(focusedURL)
    }

    package func applyMarks(matchingURLs: Set<URL>, mutation: MarkMutation) {
        let focusedURL = viewModel.focusedURL
        let visibleURLs = Set(viewModel.visibleItems.map(\.url))
        let currentMarks = Set(selectedItems.map(\.url))
        let updated = mutation.applying(matches: matchingURLs.intersection(visibleURLs), to: currentMarks)
        let rows = IndexSet(viewModel.visibleItems.enumerated().compactMap { updated.contains($0.element.url) ? $0.offset + realRowOffset : nil })
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        viewModel.setFocusedURL(focusedURL)
    }

    package func applySameExtensionMarks(_ mutation: MarkMutation) {
        guard let matches = SameExtensionMatcher.matchingURLs(focusedItem: focusedItem, visibleItems: viewModel.visibleItems) else { return }
        applyMarks(matchingURLs: matches, mutation: mutation)
    }

    package func invertSelection() {
        let allRows = Set(realRowOffset..<tableView.numberOfRows)
        let inverted = IndexSet(allRows.subtracting(tableView.selectedRowIndexes))
        tableView.selectRowIndexes(inverted, byExtendingSelection: false)
    }

    package func toggleHiddenFiles() {
        viewModel.toggleHiddenFiles()
    }

    package func setShowsHiddenFiles(_ showsHiddenFiles: Bool) {
        viewModel.setShowsHiddenFiles(showsHiddenFiles)
    }

    package func setSort(_ key: FileSortKey) {
        viewModel.setSort(key)
    }

    package func setSort(_ key: FileSortKey, ascending: Bool) {
        viewModel.setSort(key, ascending: ascending)
    }

    package func setSortDescriptor(_ descriptor: FileSortDescriptor) {
        viewModel.setSortDescriptor(descriptor)
    }

    package func setPresentationMode(_ mode: PanePresentationMode, notify: Bool = true) {
        guard presentationMode != mode else { return }
        presentationMode = mode
        presentationSelector.selectedSegment = PanePresentationMode.allCases.firstIndex(of: mode) ?? 0
        thumbnailRequests.cancelAll()
        tableView.rowHeight = mode == .gallery ? 72 : (mode == .brief ? 26 : 34)
        tableView.headerView = mode == .brief ? nil : NSTableHeaderView()
        for column in tableView.tableColumns where column.identifier.rawValue != FilePaneTableAdapter.ColumnID.name {
            column.isHidden = mode != .list
        }
        tableAdapter.applyLayout(hasOppositePane: hasOppositePane, force: true)
        requestTableReload()
        if notify { presentationDelegate?.filePane(self, didEmit: .mode(mode)) }
    }

    package func navigate(to url: URL) {
        viewModel.navigate(to: url)
    }

    /// Presents a user-initiated folder picker and stores a security-scoped
    /// grant before opening the selected directory.
    package func chooseDirectoryForAccessRecovery() {
        chooseRecoveryDirectory()
    }

    /// Clears UI state before redirecting away from an unmounted directory.
    @discardableResult
    package func fallBackIfCurrentDirectoryIsUnavailable() -> Bool {
        guard viewModel.fallBackIfCurrentDirectoryIsUnavailable() else { return false }
        selectionRestoration.prepare(nil)
        previousSelectedRowIndexes = []
        selectionRestoration.record([])
        tableView.deselectAll(nil)
        presentationDelegate?.filePane(self, didEmit: .selection([]))
        return true
    }

    /// Invalidates a directory snapshot and schedules its revalidation after a
    /// mount change. Callers must first handle unavailable directories.
    package func revalidateAfterVolumeChange() {
        viewModel.reloadAfterExternalDirectoryChange()
    }

    package func goBack() {
        selectCurrentDirectoryWhenReturningToParent(viewModel.backDestination)
        viewModel.goBack()
    }

    package func goForward() {
        viewModel.goForward()
    }

    package func goParent() {
        guard canNavigateToParent else { return }
        selectionRestoration.prepare(viewModel.currentDirectory)
        viewModel.goParent()
    }

    package func setActive(_ active: Bool) {
        guard isPaneActive != active else { return }
        isPaneActive = active
        updatePaneChrome()
        // Activation must not reload the table while AppKit is dispatching a
        // click. Updating existing row views is sufficient presentation work
        // and cannot change the clicked row's backing item.
        for row in 0..<tableView.numberOfRows {
            guard let rowView = tableView.rowView(
                atRow: row,
                makeIfNecessary: false
            ) as? FileTableRowView else { continue }
            rowView.drawsActiveSelection = active
            rowView.needsDisplay = true
        }
    }

    package func setHasOppositePane(_ hasOppositePane: Bool) {
        guard self.hasOppositePane != hasOppositePane else { return }
        self.hasOppositePane = hasOppositePane
        tableAdapter.applyLayout(hasOppositePane: hasOppositePane, force: true)
        requestTableReload()
    }

    package func updatePaneChrome() {
        activeStripe.layer?.backgroundColor = isPaneActive ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = isPaneActive ? liquidGlassStyle.activeStroke.cgColor : liquidGlassStyle.panelStroke.cgColor
        view.layer?.backgroundColor = isPaneActive ? liquidGlassStyle.activeFill.cgColor : liquidGlassStyle.panelFill.cgColor
    }

    package func focusDefaultRowForActivation() {
        selectDefaultRow()
        makeTableFirstResponder()
    }

    /// Makes keyboard commands target this pane without changing its stable
    /// focused URL or marked selection.
    package func makeTableFirstResponder() {
        view.window?.makeFirstResponder(tableView)
    }

    package func openFocusedItem() {
        if focusedDestination == .parent {
            goParent()
            return
        }
        guard let item = focusedItem else { return }
        if item.isDirectory {
            navigate(to: item.url)
        } else {
            navigationDelegate?.filePane(self, didEmit: .open(item.url))
        }
    }

    @discardableResult
    package func beginInlineRename() -> Bool {
        guard let item = focusedItem else { return false }
        guard let row = row(for: item), !isParentRow(row) else { return false }
        guard let nameColumn = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return false }
        inlineRenameRow = row
        inlineRenameItem = item
        inlineRenameSession.begin(for: item.url)
        updateInlineRenameField(at: row, for: item.url)
        tableView.scrollRowToVisible(row)
        view.window?.makeFirstResponder(tableView)
        tableView.editColumn(nameColumn, row: row, with: nil, select: true)
        selectFilenameStem(for: item)
        return true
    }

    package func handleKeyDown(_ event: NSEvent) {
        tableView.keyDown(with: event)
    }

    package func setSearchQuery(_ query: String) {
        quickSearchState.transition(from: viewModel.searchQuery, to: query, focusedURL: focusedItem?.url)
        viewModel.setSearchQuery(query)
    }

    /// Handles only table-owned quick-search gestures. Returning false leaves
    /// unsupported shortcuts on AppKit's normal responder path.
    package func handleQuickSearchKeyDown(_ event: NSEvent) -> Bool {
        guard view.window?.firstResponder === tableView else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 53, !viewModel.searchQuery.isEmpty {
            updateQuickSearchQuery("")
            return true
        }
        if event.keyCode == 51, !viewModel.searchQuery.isEmpty, modifiers.isEmpty {
            updateQuickSearchQuery(String(viewModel.searchQuery.dropLast()))
            return true
        }
        if event.keyCode == 51, viewModel.searchQuery.isEmpty, modifiers.isEmpty {
            goParent()
            return true
        }
        guard modifiers.isEmpty, let input = event.characters, !input.isEmpty,
              input.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.controlCharacters.contains(scalar)
                      && !(0xF700...0xF8FF).contains(scalar.value)
              }) else { return false }
        updateQuickSearchQuery(viewModel.searchQuery + input)
        return true
    }

    package func updateQuickSearchQuery(_ query: String) {
        setSearchQuery(query)
        presentationDelegate?.filePane(self, didEmit: .searchQuery(query))
    }

    package func setDimmedFileURLs(_ urls: [URL]) {
        dimmedFileURLs = Set(urls.map(normalizedPath))
        requestTableReload()
    }

    package func buildHeader() {
        header.material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        header.blendingMode = .withinWindow
        header.state = .active
        header.wantsLayer = true
        header.layer?.masksToBounds = true

        directoryIcon.imageScaling = .scaleProportionallyDown
        directoryIcon.setContentHuggingPriority(.required, for: .horizontal)

        hiddenButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Toggle Hidden Files".localized)
        liquidGlassStyle.applyButtonChrome(to: hiddenButton)
        hiddenButton.target = self
        hiddenButton.action = #selector(toggleHidden)
        hiddenButton.toolTip = "Toggle hidden files".localized

        presentationSelector.segmentCount = PanePresentationMode.allCases.count
        presentationSelector.segmentStyle = .texturedRounded
        presentationSelector.trackingMode = .selectOne
        for (index, mode) in PanePresentationMode.allCases.enumerated() {
            presentationSelector.setImage(NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.localizedTitle), forSegment: index)
            presentationSelector.setToolTip(mode.localizedTitle, forSegment: index)
        }
        presentationSelector.selectedSegment = 0
        presentationSelector.target = self
        presentationSelector.action = #selector(changePresentationMode)
        presentationSelector.setAccessibilityLabel("Pane presentation mode".localized)
        presentationSelector.setContentHuggingPriority(.required, for: .horizontal)
        presentationSelector.setContentCompressionResistancePriority(.required, for: .horizontal)

        hiddenButton.setContentHuggingPriority(.required, for: .horizontal)
        hiddenButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        breadcrumb.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.breadcrumb(for: paneID))
        breadcrumb.onSelect = { [weak self] url in self?.navigate(to: url) }
        tabSelector.segmentStyle = .texturedRounded
        tabSelector.trackingMode = .selectOne
        tabSelector.target = self
        tabSelector.action = #selector(selectTabSegment)
        tabSelector.setAccessibilityLabel("Pane tabs".localized)
        refreshTabSelector()
    }

    @objc private func changePresentationMode() {
        guard PanePresentationMode.allCases.indices.contains(presentationSelector.selectedSegment) else { return }
        setPresentationMode(PanePresentationMode.allCases[presentationSelector.selectedSegment])
    }

    @objc private func selectTabSegment() {
        guard viewModel.tabs.indices.contains(tabSelector.selectedSegment) else { return }
        viewModel.selectTab(id: viewModel.tabs[tabSelector.selectedSegment].id)
    }

    package func refreshTabSelector() {
        tabSelector.segmentCount = viewModel.tabs.count
        for (index, tab) in viewModel.tabs.enumerated() {
            let title = tab.currentDirectory.lastPathComponent.isEmpty ? "/" : tab.currentDirectory.lastPathComponent
            tabSelector.setLabel(title, forSegment: index)
            tabSelector.setToolTip(tab.currentDirectory.path, forSegment: index)
        }
        tabSelector.selectedSegment = viewModel.state.activeTabIndex
    }

    package func buildTable() {
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

        tableAdapter.configure(tableView: tableView, scrollView: scrollView)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
    }

    package func buildLayout() {
        [header, scrollView, contentOverlay, statusView, activeStripe].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        activeStripe.wantsLayer = true
        activeStripe.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.activeIndicator(for: paneID))
        // Keep pane actions in a trailing group that cannot be displaced by a
        // long tab or breadcrumb. A single stack makes AppKit satisfy the long
        // intrinsic widths by pushing the presentation selector outside its
        // pane while a split view is being resized.
        let locationStack = NSStackView(views: [tabSelector, directoryIcon, breadcrumb])
        locationStack.orientation = .horizontal
        locationStack.alignment = .centerY
        locationStack.spacing = 8
        locationStack.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = NSStackView(views: [presentationSelector, hiddenButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(locationStack)
        header.addSubview(actionStack)

        NSLayoutConstraint.activate([
            activeStripe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activeStripe.topAnchor.constraint(equalTo: view.topAnchor),
            activeStripe.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activeStripe.widthAnchor.constraint(equalToConstant: 3),

            header.leadingAnchor.constraint(equalTo: activeStripe.trailingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 42),

            locationStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            locationStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -8),
            locationStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            actionStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            actionStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
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

    package func bindViewModel() {
        viewModel.onChange = { [weak self] in self?.reloadData() }
        viewModel.onDirectoryChanged = { [weak self] url in self.map { $0.navigationDelegate?.filePane($0, didEmit: .directoryChanged(url)) } }
        viewModel.onDisplayPreferencesChanged = { [weak self] showsHiddenFiles, sort in
            self.map { $0.presentationDelegate?.filePane($0, didEmit: .displayPreferences(showsHiddenFiles, sort)) }
        }
        viewModel.onTabsChanged = { [weak self] in
            self?.refreshTabSelector()
            self.map { $0.presentationDelegate?.filePane($0, didEmit: .searchQuery($0.viewModel.searchQuery)) }
            if let snapshot = self?.viewModel.logicalStateSnapshot() { self.map { $0.presentationDelegate?.filePane($0, didEmit: .tabs(snapshot)) } }
        }
        reloadData()
    }

    package func item(forRow row: Int) -> FileItem? {
        let index = row - realRowOffset
        guard viewModel.visibleItems.indices.contains(index) else { return nil }
        return viewModel.visibleItems[index]
    }

    package func row(for item: FileItem) -> Int? {
        guard let index = viewModel.visibleItems.firstIndex(where: { isSameFileURL($0.url, item.url) }) else { return nil }
        return index + realRowOffset
    }

    package func isParentRow(_ row: Int) -> Bool {
        canShowParentRow && row == 0
    }

    package func row(for destination: PaneFocusDestination?) -> Int? {
        switch destination {
        case .parent: return canShowParentRow ? 0 : nil
        case let .item(url): return item(for: url).flatMap(row(for:))
        case nil: return nil
        }
    }

    package func defaultFocusRow() -> Int? {
        if !viewModel.visibleItems.isEmpty {
            return realRowOffset
        }
        if canShowParentRow {
            return 0
        }
        return nil
    }

    package func selectDefaultRow() {
        if let focusedURL = viewModel.focusedURL,
           let item = item(for: focusedURL), let row = row(for: item) {
            tableView.scrollRowToVisible(row)
            return
        }
        guard let row = defaultFocusRow(), row >= 0, row < tableView.numberOfRows else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        setFocusedDestination(isParentRow(row) ? .parent : item(forRow: row).map { .item($0.url) })
        tableView.scrollRowToVisible(row)
    }

    package func refreshAppearance(style: LiquidGlassStyle) {
        liquidGlassStyle = style
        header.material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        liquidGlassStyle.applyButtonChrome(to: hiddenButton)
        liquidGlassStyle.applyPanelChrome(to: view)
        updatePaneChrome()
        requestTableReload()
    }

    package func reloadData() {
        requestTableReload()
    }

    /// Keeps AppKit's field editor alive while the table's backing listing is
    /// changing. This is deliberately a defer/coalesce policy: the current
    /// rename is completed or cancelled before the table is rebuilt.
    package func requestTableReload() {
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

    package func performTableReload() {
        thumbnailRequests.cancelAll()
        isReloadingData = true
        defer { isReloadingData = false }
        breadcrumb.configure(url: viewModel.currentDirectory)
        directoryIcon.image = FileIconProvider.shared.image(for: FileIconKey(fileType: .folder, fileExtension: ""))
        // NSTableView otherwise preserves row indexes across reloads, which can
        // silently attach marks to different URLs after sorting or navigation.
        tableView.deselectAll(nil)
        tableView.reloadData()
        if syntheticFocusedDestination == .parent, !canShowParentRow {
            syntheticFocusedDestination = nil
        }
        pruneInvalidSelection()
        restorePreviousSelectionIfPossible()
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        if !selectPendingItemIfAvailable(), focusedItem == nil,
           viewModel.searchQuery.isEmpty, tableView.numberOfRows > 0 {
            selectDefaultRow()
        }
        selectionRestoration.record(selectedItems.map(\.url))
        configureStatusView()
        configureContentOverlay()
        presentationDelegate?.filePane(self, didEmit: .selection(selectedItems))
        let hiddenSymbol = viewModel.showsHiddenFiles ? "eye" : "eye.slash"
        hiddenButton.image = NSImage(systemSymbolName: hiddenSymbol, accessibilityDescription: "Toggle Hidden Files".localized)
    }

    package func loadThumbnail(for item: FileItem, into imageView: GalleryImageView) {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        thumbnailRequests.request(for: item.url) { [weak self, weak imageView] in
            guard let self else { return }
            let image = await thumbnailLoader.thumbnail(for: item.url, size: CGSize(width: 58, height: 58), scale: scale)
            guard !Task.isCancelled, imageView?.representedURL == item.url else { return }
            imageView?.image = image ?? FileIconProvider.shared.image(for: item.iconKey)
        }
    }

    package func flushDeferredTableReloadIfNeeded() {
        guard hasDeferredTableReload else { return }
        hasDeferredTableReload = false
        performTableReload()
    }

    package func showInlineRenameItemRemovedAlert() {
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
    package func selectPendingItemIfAvailable() -> Bool {
        guard !viewModel.isLoading, let pendingSelectionURL = selectionRestoration.pendingURL else { return false }
        let selectedURL = pendingSelectionURL
        guard let itemIndex = viewModel.visibleItems.firstIndex(where: {
            isSameFileURL($0.url, pendingSelectionURL)
        }) else { return false }
        let row = itemIndex + realRowOffset
        guard row >= 0, row < tableView.numberOfRows else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        setFocusedURL(selectedURL)
        tableView.scrollRowToVisible(row)
        self.selectionRestoration.prepare(nil)
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        selectionRestoration.record([selectedURL])
        return true
    }

    package func isSameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    /// Finder-style upward navigation should leave the folder we just left
    /// selected in its parent, including when that folder has no children.
    package func selectCurrentDirectoryWhenReturningToParent(_ destination: URL?) {
        guard let destination, isSameFileURL(destination, parentURL) else { return }
        selectionRestoration.prepare(viewModel.currentDirectory)
    }

    package func selectFilenameStem(for item: FileItem) {
        guard !item.isDirectory,
              !item.url.pathExtension.isEmpty,
              let editor = view.window?.fieldEditor(false, for: tableView) else { return }
        let stem = (item.filename as NSString).deletingPathExtension
        guard !stem.isEmpty else { return }
        editor.selectedRange = NSRange(location: 0, length: stem.count)
    }

    package func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    package func isDimmed(_ item: FileItem) -> Bool {
        dimmedFileURLs.contains(normalizedPath(item.url))
    }

    package func restorePreviousSelectionIfPossible() {
        guard selectionRestoration.pendingURL == nil, !selectionRestoration.previousURLs.isEmpty else { return }

        let rows = selectionRestoration.rows(in: viewModel.visibleItems.map(\.url), offset: realRowOffset, normalize: normalizedPath)
        guard !rows.isEmpty else { return }
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    package func configureStatusView() {
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

    package func configureContentOverlay() {
        contentOverlay.configure(
            paneID: paneID,
            isLoading: viewModel.isLoading,
            visibleItems: viewModel.visibleItems,
            errorMessage: viewModel.errorMessage,
            actions: contentOverlayActions()
        )
    }

    /// The empty-state overlay covers the synthetic `..` table row, so expose
    /// parent navigation directly in the overlay when it is safe to do so.
    /// Going through `goParent()` preserves the pending-selection behavior and
    /// the sandbox access check used by the regular parent-row interaction.
    package func contentOverlayActions() -> [PaneStatusView.Action] {
        var actions = recoveryActions()
        guard viewModel.visibleItems.isEmpty,
              !viewModel.isLoading,
              viewModel.errorMessage == nil,
              canNavigateToParent else {
            return actions
        }

        actions.insert(
            PaneStatusView.Action(
                title: "Go back".localized,
                accessibilityLabel: "Go back to parent folder".localized,
                handler: { [weak self] in self?.goParent() }
            ),
            at: 0
        )
        return actions
    }

    package func recoveryActions() -> [PaneStatusView.Action] {
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

    package func chooseRecoveryDirectory() {
        let window = view.window
        let request = AuthorizedFolderSelecting.Request(
            prompt: "Choose".localized,
            initialDirectory: viewModel.currentDirectory,
            acceptsExistingAccessibleURL: true,
            presentingWindow: window
        )
        authorizedFolderSelection.selectFolder(for: request) { [weak self] result in
            switch result {
            case .success(let url): self?.openGrantedRecoveryDirectory(url)
            case .failure(let failure): FolderAccessFailurePresenter.present(failure, in: window)
            }
        }
    }

    package func openGrantedRecoveryDirectory(_ url: URL) {
        navigationDelegate?.filePane(self, didEmit: .directoryAccessGranted(url))
        navigate(to: url)
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

extension PanePresentationMode {
    package var symbolName: String {
        switch self {
        case .list: return "list.bullet"
        case .brief: return "rectangle.compress.vertical"
        case .gallery: return "square.grid.2x2"
        }
    }
}

extension FilePaneViewController: FileTableViewActionDelegate {
    package func fileTableViewDidActivate(_ tableView: FileTableView) {
        navigationDelegate?.filePane(self, didEmit: .activate)
    }

    package func fileTableView(_ tableView: FileTableView, didFocusRow row: Int) {
        setFocusedDestination(isParentRow(row) ? .parent : item(forRow: row).map { .item($0.url) })
    }

    package func fileTableView(_ tableView: FileTableView, handleKeyDown event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        var modifiers: PaneKeyboardModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }

        switch keyboardNavigationController.action(keyCode: event.keyCode, modifiers: modifiers) {
        case let .moveFocus(delta):
            moveFocus(by: delta, in: tableView)
            return true
        case .openFocusedItem:
            // Horizontal navigation only descends into directories. Consume
            // Right Arrow on a regular file so NSTableView cannot reinterpret
            // it as a selection gesture or start an external open operation.
            if focusedItem?.isDirectory == true || focusedDestination == .parent {
                openFocusedItem()
            }
            return true
        case .navigateToParent:
            // goParent() enforces root and access-policy boundaries. The key is
            // still consumed when it declines navigation, making Left Arrow a
            // predictable no-op at either boundary.
            goParent()
            return true
        case .unhandled:
            break
        }

        if modifiers == [.command, .shift], event.keyCode == 2 {
            navigate(to: ShortcutLocations.desktop)
            return true
        }
        if modifiers == [.command, .shift], event.keyCode == 31 {
            navigate(to: ShortcutLocations.documents)
            return true
        }
        return handleQuickSearchKeyDown(event)
    }

    package func moveFocus(by delta: Int, in tableView: FileTableView) {
        guard let destination = PaneFocusNavigation.destination(
            current: focusedDestination,
            displayed: displayedDestinations,
            delta: delta
        ), let destinationRow = row(for: destination) else { return }
        // Plain arrows follow conventional file-manager behavior: move the
        // primary selection and make that row the command target. Modified
        // arrows are left to NSTableView for native range-selection behavior.
        view.window?.makeFirstResponder(tableView)
        setFocusedDestination(destination)
        tableView.selectRowIndexes(IndexSet(integer: destinationRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(destinationRow)
        tableView.setAccessibilityFocused(true)
        tableView.rowView(atRow: destinationRow, makeIfNecessary: true)?.setAccessibilityFocused(true)
    }

    package func fileTableView(_ tableView: FileTableView, contextMenuForRow row: Int) -> NSMenu? {
        if let item = item(forRow: row) { setFocusedURL(item.url) }
        if row >= 0, !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if isParentRow(row) { return contextMenuProvider.menu(for: .parent) }
        if let item = item(forRow: row) {
            return contextMenuProvider.menu(for: .item(item, hasOppositePane: hasOppositePane))
        }
        return contextMenuProvider.menu(for: .background(showsHiddenFiles: viewModel.showsHiddenFiles))
    }

}

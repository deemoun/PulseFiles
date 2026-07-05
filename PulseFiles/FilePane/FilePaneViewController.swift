import AppKit

final class FilePaneViewController: NSViewController {
    let paneID: PaneID
    let viewModel: FilePaneViewModel
    let tableView = FileTableView()

    var onActivate: (() -> Void)?
    var onSwitchPane: (() -> Void)?
    var onToggleTerminal: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onNewFile: (() -> Void)?
    var onCommand: ((MainCommand) -> Void)?
    var onDropURLs: (([URL], URL, Bool) -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?

    private let header = NSVisualEffectView()
    private let breadcrumb = BreadcrumbView()
    private let directoryIcon = NSImageView()
    private let hiddenButton = NSButton()
    private let scrollView = NSScrollView()
    private let statusView = PaneStatusView()
    private let activeStripe = NSView()
    private var isReloadingData = false
    private var isPaneActive = false
    private var previousSelectedRowIndexes = IndexSet()
    private var pendingSelectionURL: URL?

    init(paneID: PaneID, viewModel: FilePaneViewModel) {
        self.paneID = paneID
        self.viewModel = viewModel
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
        LiquidGlassStyle.applyPanelChrome(to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHeader()
        buildTable()
        buildLayout()
        bindViewModel()
    }

    func loadDirectory(selecting url: URL? = nil) {
        pendingSelectionURL = url
        viewModel.loadCurrentDirectory { [weak self] in
            self?.selectPendingItemIfAvailable()
        }
    }

    func selectItem(at url: URL) {
        pendingSelectionURL = url
        if !viewModel.isLoading {
            selectPendingItemIfAvailable()
        }
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
        activeStripe.layer?.backgroundColor = active ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = active ? LiquidGlassStyle.activeStroke.cgColor : LiquidGlassStyle.panelStroke.cgColor
        view.layer?.backgroundColor = active ? LiquidGlassStyle.activeFill.cgColor : LiquidGlassStyle.panelFill.cgColor
        tableView.reloadData()
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
            NSWorkspace.shared.open(item.url)
        }
    }

    func handleKeyDown(_ event: NSEvent) {
        tableView.keyDown(with: event)
    }

    func setSearchQuery(_ query: String) {
        viewModel.setSearchQuery(query)
    }

    private func buildHeader() {
        header.material = .hudWindow
        header.blendingMode = .withinWindow
        header.state = .active

        directoryIcon.imageScaling = .scaleProportionallyDown
        directoryIcon.setContentHuggingPriority(.required, for: .horizontal)

        hiddenButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Toggle Hidden Files")
        LiquidGlassStyle.applyButtonChrome(to: hiddenButton)
        hiddenButton.target = self
        hiddenButton.action = #selector(toggleHidden)
        hiddenButton.toolTip = "Toggle hidden files"

        breadcrumb.onSelect = { [weak self] url in self?.navigate(to: url) }
    }

    private func buildTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.actionDelegate = self
        tableView.registerForDraggedTypes([.fileURL])
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 24
        tableView.doubleAction = #selector(openDoubleClickedItem)
        tableView.target = self
        tableView.headerView = NSTableHeaderView()
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle

        addColumn(identifier: "name", title: "Name", width: 360)
        addColumn(identifier: "size", title: "Size", width: 90)
        addColumn(identifier: "modified", title: "Modified", width: 170)

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
        column.minWidth = identifier == "name" ? 180 : 70
        column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        tableView.addTableColumn(column)
    }

    private func buildLayout() {
        [header, scrollView, statusView, activeStripe].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        activeStripe.wantsLayer = true
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
        tableView.reloadData()
    }

    private func reloadData() {
        isReloadingData = true
        defer { isReloadingData = false }
        breadcrumb.configure(url: viewModel.currentDirectory)
        directoryIcon.image = .fileIcon(for: viewModel.currentDirectory)
        tableView.reloadData()
        pruneInvalidSelection()
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        if !selectPendingItemIfAvailable(), tableView.selectedRow == -1, tableView.numberOfRows > 0 {
            selectDefaultRow()
        }
        statusView.configure(
            items: viewModel.visibleItems,
            selectedItems: selectedItems,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage
        )
        let hiddenSymbol = viewModel.showsHiddenFiles ? "eye" : "eye.slash"
        hiddenButton.image = NSImage(systemSymbolName: hiddenSymbol, accessibilityDescription: "Toggle Hidden Files")
    }

    @discardableResult
    private func selectPendingItemIfAvailable() -> Bool {
        guard !viewModel.isLoading, let pendingSelectionURL else { return false }
        guard let itemIndex = viewModel.visibleItems.firstIndex(where: {
            isSameFileURL($0.url, pendingSelectionURL)
        }) else { return false }
        let row = itemIndex + realRowOffset
        guard row >= 0, row < tableView.numberOfRows else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        self.pendingSelectionURL = nil
        previousSelectedRowIndexes = tableView.selectedRowIndexes
        return true
    }

    private func isSameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
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
        let text = NSTextField(labelWithString: string(for: item, column: identifier))
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
            let imageView = NSImageView(image: item.icon)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
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
        statusView.configure(
            items: viewModel.visibleItems,
            selectedItems: selectedItems,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage
        )
        if !isReloadingData {
            onActivate?()
        }
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        switch tableColumn.identifier.rawValue {
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

    private func reloadRowsForSelectionColorChange() {
        let currentSelectedRowIndexes = tableView.selectedRowIndexes
        let changedRows = IndexSet(
            previousSelectedRowIndexes.filter { !currentSelectedRowIndexes.contains($0) }
                + currentSelectedRowIndexes.filter { !previousSelectedRowIndexes.contains($0) }
        )
        previousSelectedRowIndexes = currentSelectedRowIndexes
        guard !changedRows.isEmpty else { return }
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
        return item.url as NSURL
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropDestination(forRow: row, operation: dropOperation) != nil else { return [] }
        return NSApp.currentEvent?.modifierFlags.contains(.option) == true ? .copy : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let destination = dropDestination(forRow: row, operation: dropOperation) else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { object -> URL? in
                if let url = object as? URL { return url }
                return (object as? NSURL)?.absoluteURL
            } ?? []
        guard !urls.isEmpty else { return false }
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let isSameDirectoryMove = urls.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == destinationPath
        }
        let shouldCopy = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        guard shouldCopy || !isSameDirectoryMove else { return false }
        onDropURLs?(urls, destination, shouldCopy)
        return true
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
            let imageView = NSImageView(image: NSImage(systemSymbolName: "arrow.up.folder", accessibilityDescription: "Parent Folder") ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
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

    private func string(for item: FileItem, column: String) -> String {
        switch column {
        case "name":
            return item.displayName
        case "size":
            return FileSizeFormatter.string(fromByteCount: item.size)
        case "modified":
            return item.modificationDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        default:
            return ""
        }
    }
}

extension FilePaneViewController: FileTableViewActionDelegate {
    func fileTableViewDidActivate(_ tableView: FileTableView) {
        onActivate?()
    }

    func fileTableViewDidRequestOpen(_ tableView: FileTableView) {
        openFocusedItem()
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
            menu.addItem(contextMenuItem("Open Parent Folder", action: #selector(contextOpenParent)))
            return menu
        }

        if item(forRow: row) != nil {
            menu.addItem(contextMenuItem("Open", action: #selector(contextOpen)))
            menu.addItem(contextMenuItem("Rename", action: #selector(contextRename)))
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("Copy to Opposite Pane", action: #selector(contextCopy)))
            menu.addItem(contextMenuItem("Move to Opposite Pane", action: #selector(contextMove)))
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("Copy Path", action: #selector(contextCopyPath)))
            menu.addItem(contextMenuItem("Delete", action: #selector(contextTrash)))
        } else {
            menu.addItem(contextMenuItem("New File", action: #selector(contextNewFile)))
            menu.addItem(contextMenuItem("New Folder", action: #selector(contextNewFolder)))
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("Refresh", action: #selector(contextRefresh)))
            menu.addItem(contextMenuItem(viewModel.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files", action: #selector(contextToggleHidden)))
        }
        return menu
    }

    private func contextMenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func contextOpenParent() { onCommand?(.parent) }
    @objc private func contextOpen() { onCommand?(.open) }
    @objc private func contextRename() { onCommand?(.rename) }
    @objc private func contextCopy() { onCommand?(.copy) }
    @objc private func contextMove() { onCommand?(.move) }
    @objc private func contextTrash() { onCommand?(.trash) }
    @objc private func contextNewFile() { onCommand?(.newFile) }
    @objc private func contextNewFolder() { onCommand?(.newFolder) }
    @objc private func contextRefresh() { onCommand?(.refresh) }
    @objc private func contextToggleHidden() { onCommand?(.toggleHiddenFiles) }
    @objc private func contextCopyPath() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
}

private final class PaneContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

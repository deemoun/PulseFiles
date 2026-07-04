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
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?
    var onContextMenuCommand: ((MainCommand) -> Void)?
    var onMoveDraggedItems: (([URL], URL) -> Void)?

    private let header = NSVisualEffectView()
    private let breadcrumb = BreadcrumbView()
    private let directoryIcon = NSImageView()
    private let refreshButton = NSButton()
    private let hiddenButton = NSButton()
    private let scrollView = NSScrollView()
    private let statusView = PaneStatusView()
    private let activeStripe = NSView()

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
        tableView.selectedRowIndexes.compactMap { item(atTableRow: $0) }
    }

    var focusedItem: FileItem? {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : tableView.clickedRow
        return item(atTableRow: row)
    }

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

    func loadDirectory() {
        viewModel.loadCurrentDirectory()
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
        activeStripe.layer?.backgroundColor = active ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = active ? LiquidGlassStyle.activeStroke.cgColor : LiquidGlassStyle.panelStroke.cgColor
        view.layer?.backgroundColor = active ? LiquidGlassStyle.activeFill.cgColor : LiquidGlassStyle.panelFill.cgColor
    }

    func openFocusedItem() {
        if tableView.clickedRow == 0 || tableView.selectedRow == 0, parentDirectoryURL != nil {
            viewModel.goParent()
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

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        LiquidGlassStyle.applyButtonChrome(to: refreshButton)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.toolTip = "Refresh"

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
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: false)
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)

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
        let headerStack = NSStackView(views: [directoryIcon, breadcrumb, refreshButton, hiddenButton])
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

    private func reloadData() {
        breadcrumb.configure(url: viewModel.currentDirectory)
        directoryIcon.image = .fileIcon(for: viewModel.currentDirectory)
        tableView.reloadData()
        statusView.configure(
            items: viewModel.visibleItems,
            selectedRows: tableView.selectedRowIndexes,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage
        )
        let hiddenSymbol = viewModel.showsHiddenFiles ? "eye" : "eye.slash"
        hiddenButton.image = NSImage(systemSymbolName: hiddenSymbol, accessibilityDescription: "Toggle Hidden Files")
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
        viewModel.visibleItems.count + (parentDirectoryURL == nil ? 0 : 1)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        FileTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue else { return nil }
        if row == 0, let parentDirectoryURL {
            return parentCell(for: identifier, parent: parentDirectoryURL)
        }
        guard let item = item(atTableRow: row) else { return nil }
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: string(for: item, column: identifier))
        text.lineBreakMode = .byTruncatingMiddle
        text.textColor = LiquidGlassStyle.label
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
        statusView.configure(
            items: viewModel.visibleItems,
            selectedRows: tableView.selectedRowIndexes,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage
        )
        onActivate?()
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
        onActivate?()
        return true
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let item = item(atTableRow: row) else { return nil }
        return item.url as NSURL
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dragURLs(from: info).isEmpty == false else { return [] }
        let destination = dropDestination(forTableRow: row, operation: dropOperation)
        return destination == nil ? [] : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = dragURLs(from: info)
        guard !urls.isEmpty, let destination = dropDestination(forTableRow: row, operation: dropOperation) else { return false }
        onMoveDraggedItems?(urls, destination)
        return true
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
    func fileTableView(_ tableView: FileTableView, menuFor event: NSEvent) -> NSMenu? {
        let row = tableView.row(at: tableView.convert(event.locationInWindow, from: nil))
        if row >= 0, !tableView.selectedRowIndexes.contains(row), item(atTableRow: row) != nil {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let menu = NSMenu(title: "File Actions")
        addContextItem("Open", .open, to: menu)
        menu.addItem(.separator())
        addContextItem("New Folder", .newFolder, to: menu)
        addContextItem("New File", .newFile, to: menu)
        addContextItem("Rename", .rename, to: menu)
        menu.addItem(.separator())
        addContextItem("Copy to Other Pane", .copy, to: menu)
        addContextItem("Move to Other Pane", .move, to: menu)
        addContextItem("Move to Trash", .trash, to: menu)
        menu.addItem(.separator())
        addContextItem("Refresh", .refresh, to: menu)
        addContextItem("Go to Parent (..)", .parent, to: menu)
        return menu
    }

    func fileTableViewDidActivate(_ tableView: FileTableView) {
        onActivate?()
    }

    func fileTableViewDidRequestOpen(_ tableView: FileTableView) {
        openFocusedItem()
    }

    func fileTableViewDidRequestParent(_ tableView: FileTableView) {
        viewModel.goParent()
    }

    func fileTableViewDidRequestBack(_ tableView: FileTableView) {
        viewModel.goBack()
    }

    func fileTableViewDidRequestForward(_ tableView: FileTableView) {
        viewModel.goForward()
    }

    func fileTableView(_ tableView: FileTableView, didRequestLocation url: URL) {
        navigate(to: url)
    }

    func fileTableViewDidRequestToggleHidden(_ tableView: FileTableView) {
        toggleHiddenFiles()
    }

    func fileTableViewDidRequestTerminalToggle(_ tableView: FileTableView) {
        onToggleTerminal?()
    }

    func fileTableViewDidRequestNewFolder(_ tableView: FileTableView) {
        onNewFolder?()
    }

    func fileTableViewDidRequestNewFile(_ tableView: FileTableView) {
        onNewFile?()
    }

    func fileTableViewDidRequestPaneSwitch(_ tableView: FileTableView) {
        onSwitchPane?()
    }
}

private extension FilePaneViewController {
    var parentDirectoryURL: URL? {
        let parent = viewModel.currentDirectory.deletingLastPathComponent()
        return parent == viewModel.currentDirectory ? nil : parent
    }

    func item(atTableRow row: Int) -> FileItem? {
        let itemIndex = row - (parentDirectoryURL == nil ? 0 : 1)
        guard viewModel.visibleItems.indices.contains(itemIndex) else { return nil }
        return viewModel.visibleItems[itemIndex]
    }

    func parentCell(for identifier: String, parent: URL) -> NSView {
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: identifier == "name" ? ".." : "")
        text.textColor = LiquidGlassStyle.secondaryLabel
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        if identifier == "name" {
            let imageView = NSImageView(image: .fileIcon(for: parent))
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
        } else {
            NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        return cell
    }

    func addContextItem(_ title: String, _ command: MainCommand, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(contextMenuItemSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        menu.addItem(item)
    }

    @objc func contextMenuItemSelected(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? MainCommand else { return }
        onContextMenuCommand?(command)
    }

    func dragURLs(from info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    func dropDestination(forTableRow row: Int, operation: NSTableView.DropOperation) -> URL? {
        if operation == .on, let item = item(atTableRow: row), item.isDirectory { return item.url }
        return viewModel.currentDirectory
    }
}

private final class PaneContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

import AppKit

/// Owns table-column construction and responsive column layout. Row identity,
/// selection, focus, and view-model state remain in `FilePaneViewController`.
final class FilePaneTableAdapter {
    enum ColumnID {
        static let name = "name", fileExtension = "extension", kind = "kind", size = "size"
        static let modified = "modified", created = "created", added = "added", accessed = "accessed"
    }
    private struct Metrics { let compact: CGFloat; let minimum: CGFloat; let weight: CGFloat }
    private static let metrics: [String: Metrics] = [
        ColumnID.name: .init(compact: 300, minimum: 210, weight: 0.30),
        ColumnID.fileExtension: .init(compact: 90, minimum: 70, weight: 0.08),
        ColumnID.kind: .init(compact: 130, minimum: 110, weight: 0.12),
        ColumnID.size: .init(compact: 90, minimum: 90, weight: 0.08),
        ColumnID.modified: .init(compact: 155, minimum: 140, weight: 0.105),
        ColumnID.created: .init(compact: 155, minimum: 140, weight: 0.105),
        ColumnID.added: .init(compact: 155, minimum: 140, weight: 0.105),
        ColumnID.accessed: .init(compact: 155, minimum: 140, weight: 0.105)
    ]
    private weak var tableView: NSTableView?
    private weak var scrollView: NSScrollView?
    private var lastWidth: CGFloat = 0
    private var compactGrid = NSTableView.GridLineStyle()

    func configure(tableView: NSTableView, scrollView: NSScrollView) {
        self.tableView = tableView; self.scrollView = scrollView
        compactGrid = tableView.gridStyleMask
        add(ColumnID.name, "Name", 300, to: tableView)
        add(ColumnID.fileExtension, "Extension", 90, to: tableView)
        add(ColumnID.kind, "Kind", 130, to: tableView)
        add(ColumnID.size, "Size", 90, to: tableView)
        add(ColumnID.modified, "Modified", 155, to: tableView)
        add(ColumnID.created, "Created", 155, to: tableView)
        add(ColumnID.added, "Added", 155, to: tableView)
        add(ColumnID.accessed, "Accessed", 155, to: tableView)
    }
    private func add(_ id: String, _ title: String, _ width: CGFloat, to table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
        column.minWidth = id == ColumnID.name ? 180 : 70
        column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true); table.addTableColumn(column)
    }
    func applyLayout(hasOppositePane: Bool, force: Bool = false) {
        guard let table = tableView, let scroll = scrollView, table.tableColumns.count == Self.metrics.count else { return }
        let width = scroll.contentView.bounds.width - 1
        guard width > 0, force || abs(width - lastWidth) > 8 else { return }; lastWidth = width
        if hasOppositePane {
            scroll.hasHorizontalScroller = true; table.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle; table.gridStyleMask = compactGrid
            setWidths(Self.metrics.mapValues(\.compact), table: table)
        } else {
            scroll.hasHorizontalScroller = false; table.columnAutoresizingStyle = .noColumnAutoresizing; table.gridStyleMask = []
            let target = max(width - 2, 0), minimum = Self.metrics.mapValues(\.minimum)
            let total = minimum.values.reduce(0, +)
            let widths = target > total ? Self.metrics.mapValues { max($0.minimum, floor(target * $0.weight)) }
                : minimum.mapValues { max(70, floor($0 * (target > 0 ? target / total : 1))) }
            setWidths(widths, table: table)
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func setWidths(_ widths: [String: CGFloat], table: NSTableView) {
        for column in table.tableColumns { if let width = widths[column.identifier.rawValue], abs(column.width - width) > 1 { column.width = width } }
    }
}

// MARK: - Row rendering and AppKit table delegation

extension FilePaneViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.visibleItems.count + realRowOffset
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = FileTableRowView()
        rowView.drawsActiveSelection = isPaneActive
        rowView.drawsKeyboardFocus = self.row(for: focusedDestination) == row
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
            inlineRenameCoordinator.configure(renameTextField, itemURL: item.url, generation: inlineRenameSession.generation(for: item.url))
            text = renameTextField
        } else {
            text = NSTextField(labelWithString: string(for: item, column: identifier))
        }
        text.isEditable = identifier == "name"
        text.isBordered = false
        text.drawsBackground = false
        text.lineBreakMode = .byTruncatingMiddle
        if identifier == "name" {
            if viewModel.quickSearchPresentation == .showAllAndHighlightMatches,
               let match = viewModel.match(for: item), !match.ranges.isEmpty {
                let attributed = NSMutableAttributedString(string: item.filename)
                for range in match.ranges {
                    attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45), range: NSRange(range, in: item.filename))
                }
                text.attributedStringValue = attributed
            }
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
            let imageView = GalleryImageView(image: FileIconProvider.shared.image(for: item.iconKey))
            imageView.representedURL = item.url
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: presentationMode == .gallery ? 58 : 20),
                imageView.heightAnchor.constraint(equalToConstant: presentationMode == .gallery ? 58 : 20),
                text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.imageView = imageView
            if presentationMode == .gallery { loadThumbnail(for: item, into: imageView) }
        } else {
            text.alignment = identifier == "size" ? .right : .left
            let inset = metadataColumnContentInset
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -inset),
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
        // Selection changes not initiated by our focus-only arrow handling are
        // standard AppKit mouse, modified-key, or accessibility mark gestures.
        if !isReloadingData, tableView.selectedRow >= 0 {
            let row = tableView.selectedRow
            setFocusedDestination(isParentRow(row) ? .parent : item(forRow: row).map { .item($0.url) })
        }
        if !isReloadingData {
            viewModel.setMarkedURLs(Set(selectedItems.map(\.url)))
            previousSelectionURLs = selectedItems.map(\.url)
        }
        if !isReloadingData {
            onActivate?()
        }
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        switch tableColumn.identifier.rawValue {
        case "extension":
            setSort(.extension)
        case "kind":
            setSort(.kind)
        case "size":
            setSort(.size)
        case "modified":
            setSort(.modified)
        case "created":
            setSort(.created)
        case "added":
            setSort(.added)
        case "accessed":
            setSort(.accessed)
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
        onDropFiles?(urls, destination, operation == .copy)
        return true
    }

    private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        dropCoordinator.fileURLs(from: pasteboard)
    }

    private func resolvedDropOperation(for urls: [URL], destination: URL, pasteboard: NSPasteboard) -> DropTransferPolicy.Operation {
        dropCoordinator.operation(for: urls, destination: destination, pasteboard: pasteboard,
            optionForcesCopy: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
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
            let inset = metadataColumnContentInset
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -inset),
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
        case "extension":
            return item.fileExtension
        case "kind":
            return item.typeDescription
        case "modified":
            return item.modificationDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        case "created":
            return item.creationDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        case "added":
            return item.addedDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        case "accessed":
            return item.accessDate.map(DateFormatter.pulseFilesTableDate.string(from:)) ?? "--"
        default:
            return ""
        }
    }
}

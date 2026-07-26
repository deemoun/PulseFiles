import AppKit

final class QuickLocationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onActivate: ((QuickLocationEntry, Bool) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var entries: [QuickLocationEntry]
    private(set) var filteredEntries: [QuickLocationEntry]
    private let allowsInactivePane: Bool
    private let searchField = NSSearchField()
    private let tableView = NSTableView()

    init(entries: [QuickLocationEntry], allowsInactivePane: Bool) {
        self.entries = entries; self.filteredEntries = entries; self.allowsInactivePane = allowsInactivePane
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 440, height: 390)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(); view.setAccessibilityIdentifier(AccessibilityIdentifiers.QuickLocations.popover)
        searchField.placeholderString = "Filter locations".localized
        searchField.setAccessibilityLabel("Filter quick locations".localized)
        searchField.setAccessibilityIdentifier(AccessibilityIdentifiers.QuickLocations.search)
        searchField.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location")); column.title = "Location".localized
        tableView.addTableColumn(column); tableView.headerView = nil; tableView.delegate = self; tableView.dataSource = self
        tableView.setAccessibilityLabel("Quick locations".localized); tableView.setAccessibilityIdentifier(AccessibilityIdentifiers.QuickLocations.list)
        let scroll = NSScrollView(); scroll.documentView = tableView; scroll.hasVerticalScroller = true
        [searchField, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        selectFirstNavigable()
    }

    override func viewDidAppear() { super.viewDidAppear(); view.window?.makeFirstResponder(searchField) }
    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cell = NSTableCellView(); let label = NSTextField(labelWithString: entry.title); label.lineBreakMode = .byTruncatingMiddle
        let status = NSTextField(labelWithString: entry.availability.status ?? entry.section.title); status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 10)
        let stack = NSStackView(views: [label, status]); stack.orientation = .vertical; stack.alignment = .leading; stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack); cell.setAccessibilityIdentifier(entry.accessibilityIdentifier); cell.setAccessibilityLabel(entry.title); cell.setAccessibilityValue(entry.availability.status)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredEntries = query.isEmpty ? entries : entries.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query) || $0.section.title.localizedCaseInsensitiveContains(query) }
        tableView.reloadData(); selectFirstNavigable()
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: moveSelection(1)
        case 126: moveSelection(-1)
        case 36, 76: activateSelected(useInactive: event.modifierFlags.contains(.option))
        case 53: onCancel?()
        case 18...27:
            if event.modifierFlags.intersection([.command, .control]).isEmpty, let value = event.charactersIgnoringModifiers.flatMap(Int.init) { activate(number: value) } else { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }
    private func selectFirstNavigable() { if let row = filteredEntries.firstIndex(where: { $0.availability.isNavigable }) { tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } }
    private func moveSelection(_ delta: Int) { guard !filteredEntries.isEmpty else { return }; var row = max(0, tableView.selectedRow); for _ in filteredEntries.indices { row = (row + delta + filteredEntries.count) % filteredEntries.count; if filteredEntries[row].availability.isNavigable { tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); tableView.scrollRowToVisible(row); break } } }
    private func activate(number: Int) { let index = number == 0 ? 9 : number - 1; guard filteredEntries.indices.contains(index) else { return }; tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); activateSelected(useInactive: false) }
    private func activateSelected(useInactive: Bool) { let row = tableView.selectedRow; guard filteredEntries.indices.contains(row), filteredEntries[row].availability.isNavigable, !useInactive || allowsInactivePane else { NSSound.beep(); return }; onActivate?(filteredEntries[row], useInactive) }
}

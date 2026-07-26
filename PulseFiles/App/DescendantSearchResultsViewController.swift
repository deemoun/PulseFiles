import AppKit

/// Dedicated, non-modal results surface. It owns presentation only; all
/// filesystem-sensitive actions are delegated back to the main controller.
final class DescendantSearchResultsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum Action { case open, reveal, navigate }
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private(set) var items: [DescendantSearchItem] = []
    var onAction: ((Action, DescendantSearchItem) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 440))
        let name = NSTableColumn(identifier: .init("name")); name.title = "Name"; name.width = 260
        let location = NSTableColumn(identifier: .init("location")); location.title = "Location"; location.width = 450
        tableView.addTableColumn(name); tableView.addTableColumn(location); tableView.headerView = NSTableHeaderView(); tableView.delegate = self; tableView.dataSource = self
        tableView.target = self; tableView.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = tableView; scroll.hasVerticalScroller = true
        let open = button("Open", #selector(openSelected)); let reveal = button("Reveal", #selector(revealSelected)); let navigate = button("Navigate", #selector(navigateSelected))
        let buttons = NSStackView(views: [open, reveal, navigate]); buttons.orientation = .horizontal; buttons.spacing = 8
        [scroll, statusLabel, buttons].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -10), statusLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            buttons.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), buttons.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor)
        ])
    }

    func display(_ result: DescendantSearchResult) {
        items = result.items; tableView.reloadData()
        var suffix = result.isPartial ? " — partial results" : ""
        if !result.inaccessibleURLs.isEmpty { suffix += ", \(result.inaccessibleURLs.count) inaccessible" }
        statusLabel.stringValue = "\(items.count) results\(suffix)"
        if !items.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]; let text = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "name" ? item.name : item.pathContext)
        text.lineBreakMode = .byTruncatingMiddle; return text
    }
    private func button(_ title: String, _ action: Selector) -> NSButton { let value = NSButton(title: title, target: self, action: action); value.bezelStyle = .rounded; return value }
    private func perform(_ action: Action) { guard tableView.selectedRow >= 0 else { return }; onAction?(action, items[tableView.selectedRow]) }
    @objc private func openSelected() { perform(.open) }
    @objc private func revealSelected() { perform(.reveal) }
    @objc private func navigateSelected() { perform(.navigate) }
}

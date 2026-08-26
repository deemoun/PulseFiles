// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class DebugLogViewController: NSViewController {
    private enum ColumnIdentifier {
        static let timestamp = NSUserInterfaceItemIdentifier("DebugLogTimestampColumn")
        static let level = NSUserInterfaceItemIdentifier("DebugLogLevelColumn")
        static let category = NSUserInterfaceItemIdentifier("DebugLogCategoryColumn")
        static let message = NSUserInterfaceItemIdentifier("DebugLogMessageColumn")
    }

    private let logService: DiagnosticLogService
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let levelFilter = NSPopUpButton(frame: .zero, pullsDown: false)
    private let categoryFilter = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clearButton = NSButton(title: "Clear Logs".localized, target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Logs".localized, target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No log entries yet.".localized)
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private var allEntries: [DiagnosticLogEntry] = []
    private var filteredEntries: [DiagnosticLogEntry] = []
    private var selectedLevel: DiagnosticLogLevel?
    private var selectedCategory: String?
    private let liquidGlassStyle: LiquidGlassStyle

    init(logService: DiagnosticLogService? = nil, liquidGlassStyle: LiquidGlassStyle) {
        self.logService = logService ?? .shared
        self.liquidGlassStyle = liquidGlassStyle
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 900, height: 520)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = liquidGlassStyle.windowBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        configureTable()
        configureControls()
        rebuildLevelFilter()
        installNotifications()
        reloadEntries()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildLayout() {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let levelLabel = NSTextField(labelWithString: "Level:".localized)
        levelLabel.textColor = .secondaryLabelColor
        let categoryLabel = NSTextField(labelWithString: "Category:".localized)
        categoryLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        toolbar.addArrangedSubview(levelLabel)
        toolbar.addArrangedSubview(levelFilter)
        toolbar.addArrangedSubview(categoryLabel)
        toolbar.addArrangedSubview(categoryFilter)
        toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(copyButton)
        toolbar.addArrangedSubview(clearButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        [toolbar, scrollView, emptyLabel].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -24)
        ])
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 24
        tableView.headerView = NSTableHeaderView()

        addColumn(identifier: ColumnIdentifier.timestamp, title: "Timestamp".localized, width: 120)
        addColumn(identifier: ColumnIdentifier.level, title: "Level".localized, width: 90)
        addColumn(identifier: ColumnIdentifier.category, title: "Category".localized, width: 150)
        addColumn(identifier: ColumnIdentifier.message, title: "Message".localized, width: 520)
    }

    private func addColumn(identifier: NSUserInterfaceItemIdentifier, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = min(width, 80)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    private func configureControls() {
        levelFilter.target = self
        levelFilter.action = #selector(levelFilterChanged(_:))
        levelFilter.toolTip = "Filter debug logs by severity level.".localized
        levelFilter.setAccessibilityLabel("Debug log level filter".localized)

        categoryFilter.target = self
        categoryFilter.action = #selector(categoryFilterChanged(_:))
        categoryFilter.toolTip = "Filter debug logs by category.".localized
        categoryFilter.setAccessibilityLabel("Debug log category filter".localized)

        clearButton.target = self
        clearButton.action = #selector(clearLogs(_:))
        clearButton.bezelStyle = .rounded
        clearButton.toolTip = "Clear all debug log entries.".localized

        copyButton.target = self
        copyButton.action = #selector(copyLogs(_:))
        copyButton.bezelStyle = .rounded
        copyButton.toolTip = "Copy selected debug log entries, or all visible entries if none are selected.".localized
    }

    private func installNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(logEntriesChanged(_:)),
            name: DiagnosticLogService.entriesDidChangeNotification,
            object: logService
        )
    }

    private func reloadEntries() {
        allEntries = logService.entries
        rebuildCategoryFilter()
        applyFilters()
    }

    private func rebuildLevelFilter() {
        levelFilter.removeAllItems()
        levelFilter.addItem(withTitle: "All Levels".localized)
        DiagnosticLogLevel.allCases.forEach { level in
            levelFilter.addItem(withTitle: level.displayName)
        }
    }

    private func rebuildCategoryFilter() {
        let previousCategory = selectedCategory
        categoryFilter.removeAllItems()
        categoryFilter.addItem(withTitle: "All Categories".localized)
        let categories = Set(allEntries.map(\.category)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        categories.forEach { category in
            categoryFilter.addItem(withTitle: category)
        }
        if let previousCategory, categories.contains(previousCategory) {
            selectedCategory = previousCategory
            categoryFilter.selectItem(withTitle: previousCategory)
        } else {
            selectedCategory = nil
            categoryFilter.selectItem(at: 0)
        }
    }

    private func applyFilters() {
        filteredEntries = allEntries.filter { entry in
            if let selectedLevel, entry.level != selectedLevel { return false }
            if let selectedCategory, entry.category != selectedCategory { return false }
            return true
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filteredEntries.isEmpty
        copyButton.isEnabled = !filteredEntries.isEmpty
        clearButton.isEnabled = !allEntries.isEmpty
    }

    private func formattedLine(for entry: DiagnosticLogEntry) -> String {
        [
            timestampFormatter.string(from: entry.timestamp),
            entry.level.displayName,
            entry.category,
            entry.message
        ].joined(separator: "\t")
    }

    @objc private func logEntriesChanged(_ notification: Notification) {
        reloadEntries()
    }

    @objc private func levelFilterChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        selectedLevel = index > 0 ? DiagnosticLogLevel.allCases[index - 1] : nil
        applyFilters()
    }

    @objc private func categoryFilterChanged(_ sender: NSPopUpButton) {
        selectedCategory = sender.indexOfSelectedItem > 0 ? sender.titleOfSelectedItem : nil
        applyFilters()
    }

    @objc private func clearLogs(_ sender: Any?) {
        logService.clear()
    }

    @objc private func copyLogs(_ sender: Any?) {
        let selectedRows = tableView.selectedRowIndexes
        let entriesToCopy = selectedRows.isEmpty ? filteredEntries : selectedRows.compactMap { row in
            filteredEntries.indices.contains(row) ? filteredEntries[row] : nil
        }
        let text = entriesToCopy.map(formattedLine(for:)).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension DebugLogViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredEntries.indices.contains(row), let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("DebugLogCell-\(tableColumn.identifier.rawValue)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        if cell.textField == nil {
            cell.identifier = identifier
            cell.textField = textField
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let entry = filteredEntries[row]
        switch tableColumn.identifier {
        case ColumnIdentifier.timestamp:
            textField.stringValue = timestampFormatter.string(from: entry.timestamp)
            textField.textColor = .secondaryLabelColor
        case ColumnIdentifier.level:
            textField.stringValue = entry.level.displayName
            textField.textColor = entry.level.displayColor
        case ColumnIdentifier.category:
            textField.stringValue = entry.category
            textField.textColor = .labelColor
        default:
            textField.stringValue = entry.message
            textField.textColor = .labelColor
        }
        return cell
    }
}

private extension DiagnosticLogLevel {
    var displayName: String {
        rawValue.capitalized.localized
    }

    var displayColor: NSColor {
        switch self {
        case .debug: return .secondaryLabelColor
        case .info: return .systemBlue
        case .warning: return .systemOrange
        case .error: return .systemRed
        }
    }
}

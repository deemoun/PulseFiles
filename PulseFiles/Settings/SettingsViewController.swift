import AppKit

final class SettingsViewController: NSViewController {
    var onChange: (() -> Void)?

    private let settings: SettingsService
    private let sidebarCheckbox = NSButton(checkboxWithTitle: "Show sidebar by default", target: nil, action: nil)
    private let terminalCheckbox = NSButton(checkboxWithTitle: "Show terminal by default", target: nil, action: nil)
    private let singlePaneCheckbox = NSButton(checkboxWithTitle: "Use single pane by default", target: nil, action: nil)
    private let hiddenFilesCheckbox = NSButton(checkboxWithTitle: "Show hidden files by default", target: nil, action: nil)
    private let confirmCopyCheckbox = NSButton(checkboxWithTitle: "Confirm copy operations", target: nil, action: nil)
    private let confirmMoveCheckbox = NSButton(checkboxWithTitle: "Confirm move operations", target: nil, action: nil)
    private let confirmDeleteCheckbox = NSButton(checkboxWithTitle: "Confirm delete operations", target: nil, action: nil)
    private let permanentDeleteCheckbox = NSButton(checkboxWithTitle: "Permanent delete instead of Move to Trash", target: nil, action: nil)
    private let sidebarWidthSlider = NSSlider(value: 220, minValue: 180, maxValue: 300, target: nil, action: nil)
    private let sidebarWidthLabel = NSTextField(labelWithString: "220 pt")
    private let leftDirectoryField = NSTextField()
    private let rightDirectoryField = NSTextField()
    private var colorWells: [FileVisualCategory: NSColorWell] = [:]
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()

    init(settings: SettingsService = SettingsService()) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 820, height: 620)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        loadSettings()
    }

    private func buildLayout() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Settings")
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.setContentHuggingPriority(.required, for: .vertical)

        let subtitle = NSTextField(wrappingLabelWithString: "Configure PulseFiles defaults, startup folders, file operations, and category colors.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentHuggingPriority(.required, for: .vertical)

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        [sidebarCheckbox, terminalCheckbox, singlePaneCheckbox, hiddenFilesCheckbox, confirmCopyCheckbox, confirmMoveCheckbox, confirmDeleteCheckbox, permanentDeleteCheckbox].forEach {
            $0.target = self
            $0.action = #selector(controlChanged(_:))
        }

        sidebarWidthSlider.target = self
        sidebarWidthSlider.action = #selector(controlChanged(_:))
        sidebarWidthLabel.alignment = .right
        sidebarWidthLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        [leftDirectoryField, rightDirectoryField].forEach {
            $0.isEditable = false
            $0.isSelectable = true
            $0.lineBreakMode = .byTruncatingMiddle
        }

        let widthRow = NSStackView(views: [NSTextField(labelWithString: "Sidebar width"), sidebarWidthSlider, sidebarWidthLabel])
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 8

        let leftRow = directoryRow(title: "Left startup folder", field: leftDirectoryField, chooseAction: #selector(chooseLeftStartupDirectory(_:)), resetAction: #selector(resetLeftStartupDirectory(_:)))
        let rightRow = directoryRow(title: "Right startup folder", field: rightDirectoryField, chooseAction: #selector(chooseRightStartupDirectory(_:)), resetAction: #selector(resetRightStartupDirectory(_:)))

        let appearanceSection = settingsSection(
            title: "Appearance & Layout",
            views: [
                sidebarCheckbox,
                terminalCheckbox,
                singlePaneCheckbox,
                widthRow
            ]
        )
        let fileBrowserSection = settingsSection(
            title: "File Browser",
            views: [
                hiddenFilesCheckbox
            ]
        )
        let startupFoldersSection = settingsSection(
            title: "Startup Folders",
            views: [
                leftRow,
                rightRow
            ]
        )
        let fileOperationsSection = settingsSection(
            title: "File Operations",
            views: [
                confirmCopyCheckbox,
                confirmMoveCheckbox,
                confirmDeleteCheckbox,
                permanentDeleteCheckbox
            ]
        )
        let fileColorsSection = settingsSection(
            title: "File Colors",
            views: [
                fileColorPaletteView()
            ]
        )

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [appearanceSection, fileBrowserSection, startupFoldersSection, fileOperationsSection, fileColorsSection].forEach {
            contentStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded

        let footerStack = NSStackView(views: [doneButton])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.distribution = .gravityAreas
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(scrollView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: preferredContentSize.width),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: preferredContentSize.height),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -18),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            footerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            appearanceSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fileBrowserSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            startupFoldersSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fileOperationsSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fileColorsSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            widthRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            sidebarWidthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            leftRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            rightRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }

    private func settingsSection(title: String, views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let stack = NSStackView(views: [titleLabel] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        views.forEach { view in
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }

    private func fileColorPaletteView() -> NSView {
        let title = NSTextField(labelWithString: "File color palette")
        title.font = .preferredFont(forTextStyle: .headline)

        let description = NSTextField(wrappingLabelWithString: "PulseFiles classifies each file into the first matching category below, then uses that category color for the filename. Hidden items keep their primary category color but are dimmed. Use the color wells to override any color.")
        description.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8

        for category in FileVisualCategory.allCases {
            let row = fileColorRow(for: category)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        let resetButton = NSButton(title: "Reset Palette", target: self, action: #selector(resetFileColorPalette(_:)))

        let paletteContents = NSStackView(views: [description, rows, resetButton])
        paletteContents.orientation = .vertical
        paletteContents.alignment = .leading
        paletteContents.spacing = 10
        paletteContents.translatesAutoresizingMaskIntoConstraints = false

        let paletteBox = NSBox()
        paletteBox.boxType = .custom
        paletteBox.borderType = .lineBorder
        paletteBox.cornerRadius = 8
        paletteBox.contentViewMargins = NSSize(width: 12, height: 12)
        paletteBox.translatesAutoresizingMaskIntoConstraints = false
        paletteBox.contentView = paletteContents

        let stack = NSStackView(views: [title, paletteBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paletteBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            paletteContents.widthAnchor.constraint(equalTo: paletteBox.widthAnchor, constant: -24),
            description.widthAnchor.constraint(equalTo: paletteContents.widthAnchor),
            rows.widthAnchor.constraint(equalTo: paletteContents.widthAnchor),
            resetButton.leadingAnchor.constraint(equalTo: paletteContents.leadingAnchor)
        ])

        return stack
    }

    private func fileColorRow(for category: FileVisualCategory) -> NSStackView {
        let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
        well.target = self
        well.action = #selector(fileColorChanged(_:))
        well.tag = FileVisualCategory.allCases.firstIndex(of: category) ?? 0
        colorWells[category] = well

        let name = NSTextField(labelWithString: category.displayName)
        name.font = .preferredFont(forTextStyle: .body)
        name.widthAnchor.constraint(equalToConstant: 116).isActive = true

        let description = NSTextField(wrappingLabelWithString: category.settingsDescription)
        description.textColor = .secondaryLabelColor

        let row = NSStackView(views: [well, name, description])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        description.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func directoryRow(title: String, field: NSTextField, chooseAction: Selector, resetAction: Selector) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 124).isActive = true
        let chooseButton = NSButton(title: "Choose…", target: self, action: chooseAction)
        let resetButton = NSButton(title: "Use Last", target: self, action: resetAction)
        let row = NSStackView(views: [label, field, chooseButton, resetButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func loadSettings() {
        sidebarCheckbox.state = settings.defaultSidebarVisible ? .on : .off
        terminalCheckbox.state = settings.defaultTerminalVisible ? .on : .off
        singlePaneCheckbox.state = settings.defaultSinglePaneMode ? .on : .off
        hiddenFilesCheckbox.state = settings.showHiddenFilesByDefault ? .on : .off
        confirmCopyCheckbox.state = settings.confirmCopyOperations ? .on : .off
        confirmMoveCheckbox.state = settings.confirmMoveOperations ? .on : .off
        confirmDeleteCheckbox.state = settings.confirmDeleteOperations ? .on : .off
        permanentDeleteCheckbox.state = settings.permanentlyDeleteInsteadOfTrash ? .on : .off
        sidebarWidthSlider.doubleValue = settings.preferredSidebarWidth
        updateSidebarWidthLabel()
        updateDirectoryFields()
        updateColorWells()
    }


    private func updateColorWells() {
        let scheme = settings.fileColorScheme
        for category in FileVisualCategory.allCases {
            colorWells[category]?.color = scheme.color(for: category)
        }
    }

    private func updateSidebarWidthLabel() {
        sidebarWidthLabel.stringValue = "\(Int(settings.preferredSidebarWidth)) pt"
    }

    private func updateDirectoryFields() {
        leftDirectoryField.stringValue = settings.startupLeftDirectory?.path ?? "Last left folder (\(settings.lastLeftDirectory.path))"
        rightDirectoryField.stringValue = settings.startupRightDirectory?.path ?? "Last right folder (\(settings.lastRightDirectory.path))"
    }


    @objc private func done(_ sender: Any?) {
        dismiss(sender)
    }

    @objc private func fileColorChanged(_ sender: NSColorWell) {
        guard sender.tag >= 0, sender.tag < FileVisualCategory.allCases.count else { return }
        let category = FileVisualCategory.allCases[sender.tag]
        var colors = settings.fileColorScheme.colors
        colors[category] = sender.color
        let scheme = FileColorScheme(colors: colors)
        settings.fileColorScheme = scheme
        FileTypeColorPalette.activeScheme = scheme
        onChange?()
    }

    @objc private func resetFileColorPalette(_ sender: Any?) {
        settings.resetFileColorScheme()
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        updateColorWells()
        onChange?()
    }

    @objc private func controlChanged(_ sender: Any?) {
        settings.defaultSidebarVisible = sidebarCheckbox.state == .on
        settings.defaultTerminalVisible = terminalCheckbox.state == .on
        settings.defaultSinglePaneMode = singlePaneCheckbox.state == .on
        settings.showHiddenFilesByDefault = hiddenFilesCheckbox.state == .on
        settings.confirmCopyOperations = confirmCopyCheckbox.state == .on
        settings.confirmMoveOperations = confirmMoveCheckbox.state == .on
        settings.confirmDeleteOperations = confirmDeleteCheckbox.state == .on
        settings.permanentlyDeleteInsteadOfTrash = permanentDeleteCheckbox.state == .on
        settings.preferredSidebarWidth = sidebarWidthSlider.doubleValue
        updateSidebarWidthLabel()
        onChange?()
    }

    @objc private func chooseLeftStartupDirectory(_ sender: Any?) { chooseDirectory { [weak self] url in self?.settings.startupLeftDirectory = url; self?.updateDirectoryFields(); self?.onChange?() } }
    @objc private func chooseRightStartupDirectory(_ sender: Any?) { chooseDirectory { [weak self] url in self?.settings.startupRightDirectory = url; self?.updateDirectoryFields(); self?.onChange?() } }
    @objc private func resetLeftStartupDirectory(_ sender: Any?) { settings.startupLeftDirectory = nil; updateDirectoryFields(); onChange?() }
    @objc private func resetRightStartupDirectory(_ sender: Any?) { settings.startupRightDirectory = nil; updateDirectoryFields(); onChange?() }

    private func chooseDirectory(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let window = view.window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

import AppKit

final class SettingsViewController: NSViewController {
    private enum Category: Int, CaseIterable {
        case general
        case folders
        case operations
        case colors
#if DEBUG
        case debug
#endif

        var title: String {
            switch self {
            case .general: return "General".localized
            case .folders: return "Folders".localized
            case .operations: return "Operations".localized
            case .colors: return "Colors".localized
#if DEBUG
            case .debug: return "Debug".localized
#endif
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gearshape"
            case .folders: return "folder"
            case .operations: return "arrow.left.arrow.right"
            case .colors: return "paintpalette"
#if DEBUG
            case .debug: return "ladybug"
#endif
            }
        }
    }

    var onChange: (() -> Void)?

    private let settings: SettingsService
    private let liquidGlassCheckbox = NSButton(checkboxWithTitle: "Enable liquid glass interface".localized, target: nil, action: nil)
    private let sidebarCheckbox = NSButton(checkboxWithTitle: "Show sidebar by default".localized, target: nil, action: nil)
    private let terminalEnabledCheckbox = NSButton(checkboxWithTitle: "Enable experimental terminal".localized, target: nil, action: nil)
    private let terminalCheckbox = NSButton(checkboxWithTitle: "Show terminal by default".localized, target: nil, action: nil)
    private let singlePaneCheckbox = NSButton(checkboxWithTitle: "Use single pane by default".localized, target: nil, action: nil)
    private let hiddenFilesCheckbox = NSButton(checkboxWithTitle: "Show hidden files by default".localized, target: nil, action: nil)
    private let confirmCopyCheckbox = NSButton(checkboxWithTitle: "Confirm copy operations".localized, target: nil, action: nil)
    private let confirmMoveCheckbox = NSButton(checkboxWithTitle: "Confirm move operations".localized, target: nil, action: nil)
    private let confirmDeleteCheckbox = NSButton(checkboxWithTitle: "Confirm delete operations".localized, target: nil, action: nil)
    private let permanentDeleteCheckbox = NSButton(checkboxWithTitle: "Permanent delete instead of Move to Trash".localized, target: nil, action: nil)
#if DEBUG
    private let experimentalSandboxCheckbox = NSButton(checkboxWithTitle: "Restrict browsing and file operations to the experimental sandbox".localized, target: nil, action: nil)
#endif
    private let sidebarWidthSlider = NSSlider(value: 260, minValue: 220, maxValue: 340, target: nil, action: nil)
    private let sidebarWidthLabel = NSTextField(labelWithString: "260 pt")
    private let leftDirectoryField = NSTextField()
    private let rightDirectoryField = NSTextField()
    private var colorWells: [FileVisualCategory: NSColorWell] = [:]
    private let categoryControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private var selectedCategory: Category = .general
    private let accessPolicy = SandboxFileAccessPolicy.current
    private let accessGrantService = FolderAccessGrantService.shared

    init(settings: SettingsService = SettingsService()) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 680, height: 500)
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

    func reloadFromSettings() {
        loadSettings()
        rebuildSettingsPage()
    }

    private func buildLayout() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Settings".localized)
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.setContentHuggingPriority(.required, for: .vertical)

#if DEBUG
        let subtitleText = "Configure PulseFiles defaults, startup folders, file operations, category colors, and debug safeguards.".localized
#else
        let subtitleText = "Configure PulseFiles defaults, startup folders, file operations, and category colors.".localized
#endif
        let subtitle = NSTextField(wrappingLabelWithString: subtitleText)
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentHuggingPriority(.required, for: .vertical)

        configureCategoryControl()

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        var changeControls = [liquidGlassCheckbox, sidebarCheckbox, terminalEnabledCheckbox, terminalCheckbox, singlePaneCheckbox, hiddenFilesCheckbox, confirmCopyCheckbox, confirmMoveCheckbox, confirmDeleteCheckbox, permanentDeleteCheckbox]
#if DEBUG
        changeControls.append(experimentalSandboxCheckbox)
#endif
        changeControls.forEach {
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

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done".localized, target: self, action: #selector(done(_:)))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded

        let footerStack = NSStackView(views: [doneButton])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.distribution = .gravityAreas
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(categoryControl)
        view.addSubview(scrollView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),

            categoryControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            categoryControl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            categoryControl.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            categoryControl.heightAnchor.constraint(equalToConstant: 32),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            scrollView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -18),

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            footerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        rebuildSettingsPage()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            closeSettings()
            return
        }
        super.keyDown(with: event)
    }

    @objc override func cancelOperation(_ sender: Any?) {
        closeSettings()
    }

    private func closeSettings() {
        if let window = view.window {
            window.close()
        } else {
            dismiss(nil)
        }
    }

    private func configureCategoryControl() {
        categoryControl.segmentCount = Category.allCases.count
        categoryControl.segmentStyle = .rounded
        categoryControl.trackingMode = .selectOne
        categoryControl.target = self
        categoryControl.action = #selector(categoryChanged(_:))
        categoryControl.translatesAutoresizingMaskIntoConstraints = false

        for category in Category.allCases {
            categoryControl.setLabel(category.title, forSegment: category.rawValue)
            categoryControl.setImage(NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.title), forSegment: category.rawValue)
            categoryControl.setWidth(112, forSegment: category.rawValue)
        }
        categoryControl.selectedSegment = selectedCategory.rawValue
    }

    private func rebuildSettingsPage() {
        colorWells.removeAll()

        let pageStack = NSStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 18
        pageStack.translatesAutoresizingMaskIntoConstraints = false

        pageSections(for: selectedCategory).forEach { section in
            pageStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true
        }

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(pageStack)
        scrollView.documentView = documentView

        let documentMinimumHeight = documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        documentMinimumHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentMinimumHeight,

            pageStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            pageStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            pageStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            pageStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])

        updateColorWells()
    }

    private func pageSections(for category: Category) -> [NSView] {
        switch category {
        case .general:
            return [
                settingsSection(
                    title: "Appearance & Layout".localized,
                    views: [
                        sidebarCheckbox,
                        liquidGlassCheckbox,
                        terminalEnabledCheckbox,
                        terminalCheckbox,
                        terminalV1StatusView(),
                        singlePaneCheckbox,
                        sidebarWidthRow()
                    ]
                ),
                settingsSection(
                    title: "File Browser".localized,
                    views: [
                        hiddenFilesCheckbox
                    ]
                )
            ]
        case .folders:
            return [
                settingsSection(
                    title: "Startup Folders".localized,
                    views: [
                        directoryRow(title: "Left startup folder".localized, field: leftDirectoryField, chooseAction: #selector(chooseLeftStartupDirectory(_:)), resetAction: #selector(resetLeftStartupDirectory(_:))),
                        directoryRow(title: "Right startup folder".localized, field: rightDirectoryField, chooseAction: #selector(chooseRightStartupDirectory(_:)), resetAction: #selector(resetRightStartupDirectory(_:)))
                    ]
                )
            ]
        case .operations:
            return [
                settingsSection(
                    title: "File Operations".localized,
                    views: [
                        confirmCopyCheckbox,
                        confirmMoveCheckbox,
                        confirmDeleteCheckbox,
                        permanentDeleteCheckbox
                    ]
                )
            ]
        case .colors:
            return [
                fileColorPaletteView()
            ]
#if DEBUG
        case .debug:
            return [
                settingsSection(
                    title: "Experimental Sandbox".localized,
                    views: [
                        experimentalSandboxCheckbox,
                        sandboxRestrictionStatusView()
                    ]
                )
            ]
#endif
        }
    }


    private func terminalV1StatusView() -> NSView {
        let message = settings.experimentalTerminalEnabled
            ? "Terminal V1 is enabled. It runs shell commands in the active pane folder; commands can modify or delete files.".localized
            : "Terminal V1 is hidden by default. Enable it only if you accept the risk that shell commands can modify or delete files.".localized
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .secondaryLabelColor
        return label
    }

#if DEBUG
    private func sandboxRestrictionStatusView() -> NSView {
        let rootPath = ExperimentalFlags.appSandboxRoot.path
        let title = settings.experimentalSandboxEnabled
            ? "Experimental sandbox mode is enabled".localized
            : "Experimental sandbox mode is disabled".localized
        let message = settings.experimentalSandboxEnabled
            ? "%@\n\nSandbox root: %@".localized(with: ExperimentalFlags.sandboxRestrictionExplanation, rootPath)
            : "PulseFiles can browse real folders. Re-enable this before testing destructive file operations unless you intentionally want to work outside the test root.\n\nSandbox root: %@".localized(with: rootPath)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isSelectable = true

        let textStack = NSStackView(views: [titleLabel, messageLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            textStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            messageLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor)
        ])

        return box
    }
#endif

    private func sidebarWidthRow() -> NSStackView {
        let row = NSStackView(views: [NSTextField(labelWithString: "Sidebar width".localized), sidebarWidthSlider, sidebarWidthLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        sidebarWidthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        return row
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
        let title = NSTextField(labelWithString: "File color palette".localized)
        title.font = .preferredFont(forTextStyle: .headline)

        let description = NSTextField(wrappingLabelWithString: "PulseFiles classifies each file into the first matching category below, then uses that category color for the filename.".localized)
        description.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 14
        rows.translatesAutoresizingMaskIntoConstraints = false

        for category in FileVisualCategory.allCases {
            let row = fileColorRow(for: category)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        let resetButton = NSButton(title: "Reset Palette".localized, target: self, action: #selector(resetFileColorPalette(_:)))

        let paletteContents = NSStackView(views: [description, rows, resetButton])
        paletteContents.orientation = .vertical
        paletteContents.alignment = .leading
        paletteContents.spacing = 10
        paletteContents.translatesAutoresizingMaskIntoConstraints = false

        let paletteBox = NSView()
        paletteBox.wantsLayer = true
        paletteBox.layer?.cornerRadius = 8
        paletteBox.layer?.cornerCurve = .continuous
        paletteBox.layer?.borderWidth = 1
        paletteBox.layer?.borderColor = NSColor.separatorColor.cgColor
        paletteBox.translatesAutoresizingMaskIntoConstraints = false
        paletteBox.addSubview(paletteContents)

        let stack = NSStackView(views: [title, paletteBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paletteBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            paletteContents.leadingAnchor.constraint(equalTo: paletteBox.leadingAnchor, constant: 14),
            paletteContents.trailingAnchor.constraint(equalTo: paletteBox.trailingAnchor, constant: -14),
            paletteContents.topAnchor.constraint(equalTo: paletteBox.topAnchor, constant: 14),
            paletteContents.bottomAnchor.constraint(equalTo: paletteBox.bottomAnchor, constant: -14),
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
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        well.setContentHuggingPriority(.required, for: .horizontal)
        well.setContentCompressionResistancePriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: category.displayName)
        name.font = .preferredFont(forTextStyle: .body)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.required, for: .vertical)

        let description = NSTextField(wrappingLabelWithString: category.settingsDescription)
        description.textColor = .secondaryLabelColor
        description.setContentCompressionResistancePriority(.required, for: .vertical)

        let textStack = NSStackView(views: [name, description])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [well, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        textStack.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -72).isActive = true
        return row
    }

    private func directoryRow(title: String, field: NSTextField, chooseAction: Selector, resetAction: Selector) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 124).isActive = true
        let chooseButton = NSButton(title: "Choose…".localized, target: self, action: chooseAction)
        let resetButton = NSButton(title: "Use Last".localized, target: self, action: resetAction)
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
        liquidGlassCheckbox.state = settings.liquidGlassEnabled ? .on : .off
        terminalEnabledCheckbox.state = settings.experimentalTerminalEnabled ? .on : .off
        terminalCheckbox.state = settings.defaultTerminalVisible ? .on : .off
        terminalCheckbox.isEnabled = settings.experimentalTerminalEnabled
        singlePaneCheckbox.state = settings.defaultSinglePaneMode ? .on : .off
        hiddenFilesCheckbox.state = settings.showHiddenFilesByDefault ? .on : .off
        confirmCopyCheckbox.state = settings.confirmCopyOperations ? .on : .off
        confirmMoveCheckbox.state = settings.confirmMoveOperations ? .on : .off
        confirmDeleteCheckbox.state = settings.confirmDeleteOperations ? .on : .off
        permanentDeleteCheckbox.state = settings.permanentlyDeleteInsteadOfTrash ? .on : .off
#if DEBUG
        experimentalSandboxCheckbox.state = settings.experimentalSandboxEnabled ? .on : .off
#endif
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
        sidebarWidthLabel.stringValue = "%d pt".localized(with: Int(settings.preferredSidebarWidth))
    }

    private func updateDirectoryFields() {
        leftDirectoryField.stringValue = settings.startupLeftDirectory?.path ?? "Last left folder (%@)".localized(with: settings.lastLeftDirectory.path)
        rightDirectoryField.stringValue = settings.startupRightDirectory?.path ?? "Last right folder (%@)".localized(with: settings.lastRightDirectory.path)
    }


    @objc private func done(_ sender: Any?) {
        closeSettings()
    }

    @objc private func categoryChanged(_ sender: NSSegmentedControl) {
        guard let category = Category(rawValue: sender.selectedSegment) else { return }
        selectedCategory = category
        rebuildSettingsPage()
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
        settings.liquidGlassEnabled = liquidGlassCheckbox.state == .on
        let previousTerminalEnabled = settings.experimentalTerminalEnabled
        settings.experimentalTerminalEnabled = terminalEnabledCheckbox.state == .on
        settings.defaultTerminalVisible = settings.experimentalTerminalEnabled && terminalCheckbox.state == .on
        terminalCheckbox.isEnabled = settings.experimentalTerminalEnabled
        if previousTerminalEnabled != settings.experimentalTerminalEnabled {
            rebuildSettingsPage()
        }
        settings.defaultSinglePaneMode = singlePaneCheckbox.state == .on
        settings.showHiddenFilesByDefault = hiddenFilesCheckbox.state == .on
        settings.confirmCopyOperations = confirmCopyCheckbox.state == .on
        settings.confirmMoveOperations = confirmMoveCheckbox.state == .on
        settings.confirmDeleteOperations = confirmDeleteCheckbox.state == .on
        settings.permanentlyDeleteInsteadOfTrash = permanentDeleteCheckbox.state == .on
#if DEBUG
        let previousSandboxState = settings.experimentalSandboxEnabled
        settings.experimentalSandboxEnabled = experimentalSandboxCheckbox.state == .on
#endif
        settings.preferredSidebarWidth = sidebarWidthSlider.doubleValue
        updateSidebarWidthLabel()
#if DEBUG
        if previousSandboxState != settings.experimentalSandboxEnabled {
            ExperimentalFlags.ensureAppSandboxRootExists()
            rebuildSettingsPage()
        }
#endif
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
        panel.prompt = "Choose".localized
        let handleSelection: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let url = panel?.url else { return }
            do {
                let accessibleURL = try self.grantedDirectoryURL(for: url)
                completion(accessibleURL)
            } catch {
                self.showDirectoryAccessDeniedAlert()
            }
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func grantedDirectoryURL(for url: URL) throws -> URL {
        if accessPolicy.isEnabled {
            try accessPolicy.validateAccess(to: url)
            return url
        }

        let grant = try accessGrantService.grantAccess(to: url)
        try accessPolicy.validateAccess(to: grant.url)
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
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

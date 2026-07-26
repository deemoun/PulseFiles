import AppKit

final class SettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case general
        case folders
        case permissions
        case operations
        case colors
#if DEBUG
        case debug
#endif

        var title: String {
            switch self {
            case .general: return "General".localized
            case .folders: return "Folders".localized
            case .permissions: return "Permissions".localized
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
            case .permissions: return "lock.shield"
            case .operations: return "arrow.left.arrow.right"
            case .colors: return "paintpalette"
#if DEBUG
            case .debug: return "ladybug"
#endif
            }
        }
    }

    var onChange: (() -> Void)?
    var onOpenScratchDirectory: ((URL) -> Void)?
    var onMaintenanceCleanup: (() -> Void)?
    var onScratchCleanupResult: ((FileOperationResult, String) -> Void)?

    private let settings: SettingsService
    private let liquidGlassCheckbox = NSButton(checkboxWithTitle: "Enable liquid glass interface".localized, target: nil, action: nil)
    private let sidebarCheckbox = NSButton(checkboxWithTitle: "Show sidebar by default".localized, target: nil, action: nil)
    private let terminalEnabledCheckbox = NSButton(checkboxWithTitle: "Enable Beta Terminal".localized, target: nil, action: nil)
    private let terminalCheckbox = NSButton(checkboxWithTitle: "Show Beta Terminal by default".localized, target: nil, action: nil)
    private let singlePaneCheckbox = NSButton(checkboxWithTitle: "Use single pane by default".localized, target: nil, action: nil)
    private let hiddenFilesCheckbox = NSButton(checkboxWithTitle: "Show hidden files by default".localized, target: nil, action: nil)
    private let languageSelector = NSPopUpButton()
    private let confirmCopyCheckbox = NSButton(checkboxWithTitle: "Confirm copy operations".localized, target: nil, action: nil)
    private let confirmMoveCheckbox = NSButton(checkboxWithTitle: "Confirm move operations".localized, target: nil, action: nil)
    private let confirmDeleteCheckbox = NSButton(checkboxWithTitle: "Confirm delete operations".localized, target: nil, action: nil)
    private let permanentDeleteCheckbox = NSButton(checkboxWithTitle: "Permanent delete instead of Move to Trash".localized, target: nil, action: nil)
    private lazy var clearIncompleteTransfersButton = NSButton(title: "Clear Incomplete Transfers…".localized, target: self, action: #selector(clearIncompleteTransfers(_:)))
#if DEBUG
    private let experimentalSandboxCheckbox = NSButton(checkboxWithTitle: "Restrict browsing and file operations to the experimental sandbox".localized, target: nil, action: nil)
#endif
    private let sidebarWidthSlider = NSSlider(value: 260, minValue: 220, maxValue: 340, target: nil, action: nil)
    private let sidebarWidthLabel = NSTextField(labelWithString: "260 pt")
    private let leftDirectoryField = NSTextField()
    private let rightDirectoryField = NSTextField()
    private let scratchDirectoryField = NSTextField()
    private var colorWells: [FileVisualCategory: NSColorWell] = [:]
    private let categoryControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private var selectedCategory: Category = .general
    private let accessPolicy = SandboxFileAccessPolicy.current
    private let accessGrantService = FolderAccessGrantService.shared
    private let standardFolderAccessService = StandardFolderAccessService()
    private let stagingCleanupService: StagingCleanupService
    private let scratchCleanupService: ScratchFolderCleanupService
    private var standardFolderAccessStates: [StandardFolder: StandardFolderAccessState] = [:]

    init(
        settings: SettingsService = SettingsService(),
        stagingCleanupService: StagingCleanupService = StagingCleanupService(),
        scratchCleanupService: ScratchFolderCleanupService = ScratchFolderCleanupService()
    ) {
        self.settings = settings
        self.stagingCleanupService = stagingCleanupService
        self.scratchCleanupService = scratchCleanupService
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
        configureLanguageSelector()

        [leftDirectoryField, rightDirectoryField, scratchDirectoryField].forEach {
            $0.isEditable = false
            $0.isSelectable = true
            $0.lineBreakMode = .byTruncatingMiddle
        }
        scratchDirectoryField.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.scratchPath)

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
                    title: "Language".localized,
                    views: [languageRow()]
                ),
                settingsSection(
                    title: "Appearance & Layout".localized,
                    views: [
                        sidebarCheckbox,
                        liquidGlassCheckbox,
                        terminalEnabledCheckbox,
                        terminalCheckbox,
                        experimentalTerminalStatusView(),
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
                ),
                settingsSection(title: "Temporary Workspace".localized, views: [scratchDirectoryRow()])
            ]
        case .permissions:
            return [
                settingsSection(
                    title: "Effective Access Mode".localized,
                    views: [effectiveAccessModeView()]
                ),
                settingsSection(
                    title: "Folder Access Grants".localized,
                    views: [folderAccessGrantsView()]
                ),
                settingsSection(
                    title: "Files & Folders Access".localized,
                    views: [privacyPermissionsExplanationView()]
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
                ),
                settingsSection(
                    title: "Storage & Maintenance".localized,
                    views: [clearIncompleteTransfersButton]
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

    @objc private func clearIncompleteTransfers(_ sender: Any?) {
        clearIncompleteTransfersButton.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let inventory = await Task.detached(priority: .utility) { self.stagingCleanupService.inventory() }.value
            let alert = NSAlert()
            alert.messageText = "Clear Incomplete Transfers?".localized
            var detail = "%@ safely identifiable abandoned item(s), using %@.".localized(with: inventory.candidates.count, FileSizeFormatter.string(fromByteCount: inventory.totalByteCount))
            if !inventory.legacyItemsForReview.isEmpty {
                let paths = inventory.legacyItemsForReview.map(\.path).joined(separator: "\n")
                detail += "\n\nThese legacy similarly named items are shown for review and will not be deleted automatically:\n%@".localized(with: paths)
            }
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Clear Identified Items".localized)
            alert.addButton(withTitle: "Cancel".localized)
            guard alert.runModal() == .alertFirstButtonReturn else {
                self.clearIncompleteTransfersButton.isEnabled = true
                return
            }
            let result = await self.stagingCleanupService.cleanup(inventory.candidates)
            self.clearIncompleteTransfersButton.isEnabled = true
            self.onMaintenanceCleanup?()
            let report = NSAlert()
            report.messageText = result.failures.isEmpty ? "Incomplete transfers cleared".localized : "Some incomplete transfers could not be cleared".localized
            report.informativeText = result.failures.isEmpty
                ? "%@ item(s) removed.".localized(with: result.removed.count)
                : result.failures.map { "\($0.url.path): \($0.message)" }.joined(separator: "\n")
            report.runModal()
        }
    }

    private func effectiveAccessModeView() -> NSView {
        let title = accessPolicy.isEnabled
            ? "DEBUG experimental sandbox is enabled".localized
            : "Normal macOS-governed file-manager access".localized
        let message = accessPolicy.isEnabled
            ? "File access is limited to the experimental sandbox root unless a folder has an explicit security-scoped grant. Sandbox root: %@".localized(with: accessPolicy.rootURL.path)
            : "PulseFiles uses the access that macOS allows for this app. Protected locations and folder grants are still checked through the file access policy.".localized
        return permissionStatusView(title: title, message: message)
    }

    private func folderAccessGrantsView() -> NSView {
        let explanation = NSTextField(wrappingLabelWithString: "Security-scoped bookmarks from Grant Folder Access… are separate from macOS Files & Folders privacy status.".localized)
        explanation.textColor = .secondaryLabelColor
        explanation.isSelectable = true
        let grants = accessGrantService.grants
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8

        if grants.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No persisted folder access grants.".localized)
            empty.textColor = .secondaryLabelColor
            rows.addArrangedSubview(empty)
        } else {
            for grant in grants {
                let grantStatus = accessGrantService.grantStatus(
                    containing: grant.url,
                    canRead: { FileManager.default.fileExists(atPath: $0) && FileManager.default.isReadableFile(atPath: $0) },
                    canWrite: FileManager.default.isWritableFile(atPath:)
                )
                let path = NSTextField(labelWithString: grant.url.path)
                path.lineBreakMode = .byTruncatingMiddle
                path.toolTip = grant.url.path
                let statusText: String
                let statusColor: NSColor
                switch grantStatus {
                case .available:
                    statusText = "Available".localized
                    statusColor = .secondaryLabelColor
                case .staleOrUnavailable:
                    statusText = "Stale or unavailable".localized
                    statusColor = .systemOrange
                case .inaccessible, .noMatchingGrant:
                    statusText = "Currently inaccessible".localized
                    statusColor = .systemOrange
                }
                let state = NSTextField(labelWithString: statusText)
                state.textColor = statusColor
                let revoke = FolderAccessGrantButton(title: "Revoke".localized, target: self, action: #selector(revokeFolderAccess(_:)))
                revoke.grantURL = grant.url
                let row = NSStackView(views: [path, state, revoke])
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 8
                path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
        }

        let grant = NSButton(title: "Grant Folder Access…".localized, target: self, action: #selector(grantFolderAccess(_:)))
        let refresh = NSButton(title: "Refresh Grant Status".localized, target: self, action: #selector(refreshFolderAccessGrants(_:)))
        let controls = NSStackView(views: [grant, refresh])
        controls.orientation = .horizontal
        controls.spacing = 8
        let stack = NSStackView(views: [explanation, rows, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        rows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func privacyPermissionsExplanationView() -> NSView {
        let message = NSTextField(wrappingLabelWithString: "Select a folder to ask macOS for access when it is needed for dual-pane browsing or confirmed file operations. PulseFiles cannot grant Full Disk Access or change a macOS privacy decision itself.".localized)
        message.textColor = .secondaryLabelColor
        message.isSelectable = true
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        for folder in StandardFolder.allCases {
            let row = standardFolderAccessRow(for: folder)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        let recovery = NSButton(title: "Open Privacy Settings".localized, target: self, action: #selector(openPrivacySettings(_:)))
        recovery.toolTip = "Open macOS privacy settings to review Files & Folders access.".localized
        let stack = NSStackView(views: [message, rows, recovery])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        rows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func standardFolderAccessRow(for folder: StandardFolder) -> NSView {
        let title = NSTextField(labelWithString: folder.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let status = NSTextField(wrappingLabelWithString: standardFolderAccessMessage(for: folder))
        status.textColor = .secondaryLabelColor
        status.isSelectable = true
        let request = NSButton(title: "Request Access".localized, target: self, action: #selector(requestStandardFolderAccess(_:)))
        request.identifier = NSUserInterfaceItemIdentifier(folder.rawValue)
        request.setAccessibilityLabel("Request access to %@".localized(with: folder.title))
        request.toolTip = "Ask macOS for access to %@ when needed.".localized(with: folder.title)
        let sandboxBlocked = accessPolicy.isEnabled && !accessPolicy.canAttemptProtectedFolderAccess(standardFolderAccessService.url(for: folder) ?? accessPolicy.rootURL)
        request.isEnabled = !sandboxBlocked
        let text = NSStackView(views: [title, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, request])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        request.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func standardFolderAccessMessage(for folder: StandardFolder) -> String {
        switch standardFolderAccessStates[folder] {
        case .accessible: return "Accessible. PulseFiles completed a minimal folder read.".localized
        case .deniedOrUnavailable: return "Denied or unavailable. Verify the folder exists and review access in System Settings if needed.".localized
        case .requiresSystemSettingsReview: return "Requires review in System Settings. PulseFiles cannot change this privacy decision.".localized
        case .blockedByExperimentalSandbox: return "Experimental sandbox mode blocks this folder unless it has a separate folder-access grant.".localized
        case nil: return "Selecting Request Access asks macOS for access when needed.".localized
        }
    }

    private func permissionStatusView(title: String, message: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isSelectable = true
        let stack = NSStackView(views: [titleLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }


    private func experimentalTerminalStatusView() -> NSView {
        let message = settings.experimentalTerminalEnabled
            ? "Beta Terminal is enabled. Shell commands can modify or delete files in the active pane folder.".localized
            : "Beta Terminal is disabled and hidden. Enable it only if you accept that shell commands can modify or delete files.".localized
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

    private func scratchDirectoryRow() -> NSStackView {
        let choose = NSButton(title: "Choose Folder…".localized, target: self, action: #selector(chooseScratchDirectory(_:)))
        let open = NSButton(title: "Open in Active Pane".localized, target: self, action: #selector(openScratchDirectory(_:)))
        let clear = NSButton(title: "Clear Setting".localized, target: self, action: #selector(clearScratchDirectory(_:)))
        let clean = NSButton(title: "Clean Up Contents…".localized, target: self, action: #selector(cleanScratchDirectory(_:)))
        choose.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.chooseScratchFolder)
        open.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.openScratchFolder)
        clear.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.clearScratchFolder)
        open.isEnabled = settings.scratchDirectory != nil
        clean.isEnabled = settings.scratchFolderSelection != nil
        clear.isEnabled = settings.scratchDirectory != nil
        let controls = NSStackView(views: [choose, open, clean, clear])
        controls.orientation = .horizontal
        controls.spacing = 8
        let row = NSStackView(views: [scratchDirectoryField, controls])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 8
        scratchDirectoryField.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func loadSettings() {
        languageSelector.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.appLanguage) ?? 0)
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

    private func configureLanguageSelector() {
        languageSelector.removeAllItems()
        AppLanguage.allCases.forEach { languageSelector.addItem(withTitle: $0.localizedDisplayName) }
        languageSelector.target = self
        languageSelector.action = #selector(languageChanged(_:))
        languageSelector.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.languageSelector)
    }

    private func languageRow() -> NSView {
        let label = NSTextField(labelWithString: "App language".localized)
        let restart = NSTextField(wrappingLabelWithString: "Language changes apply after restarting PulseFiles.".localized)
        restart.textColor = .secondaryLabelColor
        let text = NSStackView(views: [label, restart])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, languageSelector])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.appLanguage = AppLanguage.allCases[sender.indexOfSelectedItem]
        onChange?()
    }

    var appLanguageSelectorForTesting: NSPopUpButton { languageSelector }


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
        scratchDirectoryField.stringValue = settings.scratchDirectory?.path ?? "No scratch folder configured".localized
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

    @objc private func grantFolderAccess(_ sender: Any?) {
        accessGrantService.requestGrant(startingAt: nil, window: view.window) { [weak self] result in
            guard let self else { return }
            self.accessGrantService.refreshResolvedGrants()
            self.rebuildSettingsPage()
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                self.showFolderGrantFailureAlert(error)
            }
        }
    }

    @objc private func refreshFolderAccessGrants(_ sender: Any?) {
        accessGrantService.refreshResolvedGrants()
        rebuildSettingsPage()
    }

    @objc private func revokeFolderAccess(_ sender: FolderAccessGrantButton) {
        guard let url = sender.grantURL else { return }
        _ = accessGrantService.removeGrant(for: url)
        rebuildSettingsPage()
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
    @objc private func chooseScratchDirectory(_ sender: Any?) {
        chooseDirectory { [weak self] url in
            guard let self else { return }
            do {
                let selection = try self.scratchCleanupService.captureSelection(for: url)
                self.settings.scratchDirectory = selection.directory
                self.settings.scratchFolderSelection = selection
            } catch {
                self.presentScratchCleanupError(error)
                return
            }
            self.updateDirectoryFields()
            self.rebuildSettingsPage()
            self.onChange?()
        }
    }
    @objc private func openScratchDirectory(_ sender: Any?) {
        guard let url = settings.scratchDirectory, accessPolicy.canAccess(url) else { return }
        onOpenScratchDirectory?(url)
    }
    @objc private func clearScratchDirectory(_ sender: Any?) {
        settings.scratchDirectory = nil
        updateDirectoryFields()
        rebuildSettingsPage()
        onChange?()
    }

    @objc private func cleanScratchDirectory(_ sender: Any?) {
        guard let selection = settings.scratchFolderSelection else { return }
        do {
            let inventory = try scratchCleanupService.inventory(for: selection)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Clean Up Scratch Folder Contents?".localized
            alert.informativeText = [
                "Folder: %@".localized(with: inventory.selection.directory.path),
                "Items: %d".localized(with: inventory.itemCount),
                "Allocated size: %@".localized(with: FileSizeFormatter.string(fromByteCount: inventory.allocatedByteCount)),
                "Only the folder's contents will be affected. The configured folder itself will remain.".localized,
                "Move Contents to Trash is recoverable until the Trash is emptied. Permanently Delete cannot be undone.".localized
            ].joined(separator: "\n")
            alert.addButton(withTitle: "Move Contents to Trash".localized)
            alert.addButton(withTitle: "Permanently Delete…".localized)
            alert.addButton(withTitle: "Cancel — Keep Contents".localized)
            let response = alert.runModal()
            guard response != .alertThirdButtonReturn else { return }
            let action: ScratchFolderCleanupAction = response == .alertFirstButtonReturn ? .moveToTrash : .permanentlyDelete
            if action == .permanentlyDelete {
                let confirmation = NSAlert()
                confirmation.alertStyle = .critical
                confirmation.messageText = "Permanently Delete Scratch Folder Contents?".localized
                confirmation.informativeText = "This permanently deletes %d item(s) from %@ and cannot be undone. The folder itself will remain.".localized(with: inventory.itemCount, inventory.selection.directory.path)
                confirmation.addButton(withTitle: "Permanently Delete Contents".localized)
                confirmation.addButton(withTitle: "Cancel — Keep Contents".localized)
                guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.scratchCleanupService.cleanup(inventory, action: action)
                    self.onScratchCleanupResult?(result, action == .moveToTrash ? "Move to Trash".localized : "Permanently Delete".localized)
                } catch {
                    self.presentScratchCleanupError(error)
                }
            }
        } catch {
            presentScratchCleanupError(error)
        }
    }

    private func presentScratchCleanupError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func requestStandardFolderAccess(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue, let folder = StandardFolder(rawValue: identifier) else { return }
        standardFolderAccessStates[folder] = standardFolderAccessService.requestAccess(for: folder)
        rebuildSettingsPage()
    }

    @objc private func openPrivacySettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }

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
        if accessPolicy.canAccess(url) {
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

    private func showFolderGrantFailureAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Grant Folder Access".localized
        alert.informativeText = "PulseFiles could not create a secure folder-access bookmark. No additional folder access was granted. %@".localized(with: error.localizedDescription)
        alert.addButton(withTitle: "OK".localized)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private final class FolderAccessGrantButton: NSButton {
    var grantURL: URL?
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let editSettingsJSONDebugDefaultsKey = "PulseFilesShowEditSettingsJSONMenuItem"
    static let editSettingsJSONDebugLaunchArgument = "--pulsefiles-show-edit-settings-json-menu-item"

    private let launchArguments: [String]
    private let userDefaults: UserDefaults
    private let settings: SettingsService
    private let accessPolicy: SandboxFileAccessPolicy
    private let fileManager: FileManager
    private let mainWindowControllerFactory: (SettingsService) -> MainWindowController

    private var mainWindowController: MainWindowController?
    private var aboutWindowController: NSWindowController?

    private static let supportURL = URL(string: "https://github.com/deemoun/PulseFiles/issues")!
    private static let privacyPolicyURL = URL(string: "https://github.com/deemoun/PulseFiles/blob/main/PRIVACY.md")!
    private static let issueReportingURL = URL(string: "https://github.com/deemoun/PulseFiles/issues/new/choose")!

    @MainActor
    static func makeProductionMainWindowController(
        settings: SettingsService,
        accessPolicy: SandboxFileAccessPolicy = .current,
        sandboxRootEnsurer: @escaping () -> Void = ExperimentalFlags.ensureAppSandboxRootExists
    ) -> MainWindowController {
        let dependencies = MainWindowDependencies.production(accessPolicy: accessPolicy)
        return MainWindowController(
            settings: settings,
            dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: accessPolicy),
            sandboxRootEnsurer: sandboxRootEnsurer
        )
    }

    init(
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard,
        settings: SettingsService? = nil,
        accessPolicy: SandboxFileAccessPolicy = .current,
        fileManager: FileManager = .default,
        mainWindowControllerFactory: ((SettingsService) -> MainWindowController)? = nil
    ) {
        let settings = settings ?? SettingsService(defaults: userDefaults, accessPolicy: accessPolicy)
        self.launchArguments = launchArguments
        self.userDefaults = userDefaults
        self.settings = settings
        self.accessPolicy = accessPolicy
        self.fileManager = fileManager
        self.mainWindowControllerFactory = mainWindowControllerFactory ?? { settings in
            Self.makeProductionMainWindowController(settings: settings, accessPolicy: accessPolicy)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) {
            _ = await StagingCleanupService().cleanupOnStartup()
        }
        LocalizationConfiguration.configure(language: settings.appLanguage)
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        if let icon = appIcon() {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.mainMenu = buildMainMenu()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Finder and Launch Services deliver document-open events here. PulseFiles
    /// registers only for folders, but handles file URLs defensively because an
    /// event can still be forwarded by another app or automation tool.
    func application(_ application: NSApplication, open urls: [URL]) {
        let result = OpenEventRouter.route(urls, accessPolicy: accessPolicy, fileManager: fileManager)
        guard let directory = result.firstAcceptedFolder else { return }

        let controller = showMainWindow()
        controller.contentViewController?.view.layoutSubtreeIfNeeded()
        (controller.contentViewController as? MainWindowViewController)?.openAcceptedFolderFromExternalEvent(directory)
    }

    /// Reopen recreates or brings forward the main file-manager window. This is
    /// intentionally independent of the open-event path so a Dock reopen does
    /// not alter either pane's current directory.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        _ = showMainWindow()
        return true
    }

    @discardableResult
    private func showMainWindow() -> MainWindowController {
        let controller: MainWindowController
        if let existing = mainWindowController, existing.window != nil {
            controller = existing
        } else {
            controller = mainWindowControllerFactory(settings)
            mainWindowController = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        configureSortMenuTargets(for: controller)
        return controller
    }

    /// Sort commands must always reach the main window controller. Depending on
    /// which AppKit control is first responder, responder-chain dispatch can
    /// stop before reaching the content view controller, leaving the View menu
    /// items enabled but with no effect. Other file commands intentionally use
    /// normal responder-chain routing; these display preferences are scoped to
    /// the active pane and have one unambiguous window-level handler.
    private func configureSortMenuTargets(for controller: MainWindowController) {
        guard let contentController = controller.contentViewController as? MainWindowViewController,
              let mainMenu = NSApplication.shared.mainMenu else {
            return
        }

        setSortMenuTarget(contentController, in: mainMenu)
    }

    private func setSortMenuTarget(_ target: MainWindowViewController, in menu: NSMenu) {
        for item in menu.items {
            if isSortMenuAction(item.action) {
                item.target = target
            }
            if let submenu = item.submenu {
                setSortMenuTarget(target, in: submenu)
            }
        }
    }

    private func isSortMenuAction(_ action: Selector?) -> Bool {
        switch action {
        case #selector(MainWindowViewController.menuSortByName(_:)),
             #selector(MainWindowViewController.menuSortByExtension(_:)),
             #selector(MainWindowViewController.menuSortByKind(_:)),
             #selector(MainWindowViewController.menuSortBySize(_:)),
             #selector(MainWindowViewController.menuSortByModified(_:)),
             #selector(MainWindowViewController.menuSortByCreated(_:)),
             #selector(MainWindowViewController.menuSortByAdded(_:)),
             #selector(MainWindowViewController.menuSortByAccessed(_:)),
             #selector(MainWindowViewController.menuSortAscending(_:)),
             #selector(MainWindowViewController.menuSortDescending(_:)):
            true
        default:
            false
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        (mainWindowController?.contentViewController as? MainWindowViewController)?.reloadSettingsFromJSONIfChanged()
    }

    func buildMainMenu() -> NSMenu {
        let menu = NSMenu(title: "PulseFiles")
        menu.addItem(appMenu())
        menu.addItem(fileMenu())
        menu.addItem(editMenu())
        menu.addItem(viewMenu())
        menu.addItem(goMenu())
        menu.addItem(commandMenu())
        menu.addItem(windowMenu())
        menu.addItem(helpMenu())
        return menu
    }

    private func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "PulseFiles")
        let aboutItem = NSMenuItem(title: "About PulseFiles".localized, action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        submenu.addItem(aboutItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Settings…".localized, action: #selector(MainWindowViewController.menuSettings(_:)), key: ",", modifiers: [.command]))
        if showsEditSettingsJSONMenuItem {
            submenu.addItem(menuItem("Edit Settings JSON…".localized, action: #selector(MainWindowViewController.menuEditSettingsJSON(_:)), key: ",", modifiers: [.command, .option]))
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit PulseFiles".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        return item
    }

    private var showsEditSettingsJSONMenuItem: Bool {
        launchArguments.contains(Self.editSettingsJSONDebugLaunchArgument)
            || userDefaults.bool(forKey: Self.editSettingsJSONDebugDefaultsKey)
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        if let existingWindow = aboutWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 460))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconView = NSImageView()
        iconView.image = appIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "PulseFiles")
        nameLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "Version %@".localized(with: version))
        versionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Dual-pane file manager for macOS".localized)
        descriptionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let attributionLabel = NSTextField(labelWithString: "Created by Dmitry Yarygin".localized)
        attributionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        attributionLabel.textColor = .secondaryLabelColor
        attributionLabel.alignment = .center
        attributionLabel.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done".localized, target: self, action: #selector(closeAbout(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        [iconView, nameLabel, versionLabel, descriptionLabel, attributionLabel, doneButton].forEach(contentView.addSubview)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 188),
            iconView.heightAnchor.constraint(equalToConstant: 188),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            versionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            descriptionLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 18),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            attributionLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            attributionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            attributionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            doneButton.topAnchor.constraint(greaterThanOrEqualTo: attributionLabel.bottomAnchor, constant: 24),
            doneButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About PulseFiles".localized
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        aboutWindowController = windowController
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func closeAbout(_ sender: Any?) {
        aboutWindowController?.window?.close()
    }

    private func appIcon() -> NSImage? {
        if let resourceIcon = NSImage(named: "AppIcon") {
            return resourceIcon
        }
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
    }

    private func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "File".localized)
        submenu.addItem(menuItem("New File".localized, action: #selector(MainWindowViewController.menuNewFile(_:)), command: .newFile))
        submenu.addItem(menuItem("New Folder".localized, action: #selector(MainWindowViewController.menuNewFolder(_:)), command: .newFolder))
        submenu.addItem(menuItem("Rename".localized, action: #selector(MainWindowViewController.menuRename(_:)), command: .rename))
        submenu.addItem(menuItem("Batch Rename…".localized, action: #selector(MainWindowViewController.menuBatchRename(_:)), command: .batchRename))
        submenu.addItem(menuItem("Create Archive…".localized, action: #selector(MainWindowViewController.menuCreateArchive(_:)), command: .createArchive))
        submenu.addItem(menuItem("Extract Archive…".localized, action: #selector(MainWindowViewController.menuExtractArchive(_:)), command: .extractArchive))
        submenu.addItem(menuItem("Duplicate".localized, action: #selector(MainWindowViewController.menuDuplicate(_:)), command: .duplicate))
        submenu.addItem(menuItem("Get Info".localized, action: #selector(MainWindowViewController.menuGetInfo(_:)), command: .getInfo))
        submenu.addItem(menuItem("Viewer".localized, action: #selector(MainWindowViewController.menuViewer(_:)), command: .viewer))
        submenu.addItem(menuItem("Open With…".localized, action: #selector(MainWindowViewController.menuOpenWith(_:)), command: .openWith))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Move to Trash".localized, action: #selector(MainWindowViewController.menuMoveToTrash(_:)), command: .trash))
        item.submenu = submenu
        return item
    }

    private func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Edit".localized)
        submenu.addItem(menuItem("Undo".localized, action: #selector(MainWindowViewController.menuUndo(_:)), command: .undo))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy".localized, action: #selector(MainWindowViewController.menuCopyToClipboard(_:)), command: .copyToClipboard))
        submenu.addItem(menuItem("Cut".localized, action: #selector(MainWindowViewController.menuCutToClipboard(_:)), command: .cutToClipboard))
        submenu.addItem(menuItem("Paste".localized, action: #selector(MainWindowViewController.menuPasteFromClipboard(_:)), command: .pasteFromClipboard))
        submenu.addItem(menuItem("Select All".localized, action: #selector(MainWindowViewController.menuSelectAll(_:)), command: .selectAll))
        submenu.addItem(menuItem("Deselect All".localized, action: #selector(MainWindowViewController.menuDeselectAll(_:)), command: .deselectAll))
        submenu.addItem(menuItem("Select by Pattern…".localized, action: #selector(MainWindowViewController.menuSelectByPattern(_:)), command: .selectByPattern))
        submenu.addItem(menuItem("Deselect by Pattern…".localized, action: #selector(MainWindowViewController.menuDeselectByPattern(_:)), command: .deselectByPattern))
        submenu.addItem(menuItem("Select Same Extension".localized, action: #selector(MainWindowViewController.menuSelectSameExtension(_:)), command: .selectSameExtension))
        submenu.addItem(menuItem("Deselect Same Extension".localized, action: #selector(MainWindowViewController.menuDeselectSameExtension(_:)), command: .deselectSameExtension))
        submenu.addItem(menuItem("Invert Selection".localized, action: #selector(MainWindowViewController.menuInvertSelection(_:)), command: .invertSelection))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Cancel Operation".localized, action: #selector(MainWindowViewController.menuCancelOperation(_:)), command: .cancelOperation))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy to Opposite Pane".localized, action: #selector(MainWindowViewController.menuCopy(_:)), command: .copy))
        submenu.addItem(menuItem("Move to Opposite Pane".localized, action: #selector(MainWindowViewController.menuMove(_:)), command: .move))
        submenu.addItem(menuItem("Reveal in Opposite Pane".localized, action: #selector(MainWindowViewController.menuRevealInOppositePane(_:)), command: .revealInOppositePane))
        item.submenu = submenu
        return item
    }

    private func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "View".localized)
        submenu.addItem(menuItem("Refresh".localized, action: #selector(MainWindowViewController.menuRefresh(_:)), command: .refresh))
        submenu.addItem(menuItem("Reveal in Finder".localized, action: #selector(MainWindowViewController.menuReveal(_:)), command: .reveal))
        submenu.addItem(menuItem("Show Hidden Files".localized, action: #selector(MainWindowViewController.menuToggleHiddenFiles(_:)), command: .toggleHiddenFiles))
        submenu.addItem(.separator())
        let presentationSubmenu = NSMenu(title: "Presentation".localized)
        presentationSubmenu.addItem(menuItem("List".localized, action: #selector(MainWindowViewController.menuPresentationList(_:)), key: "", modifiers: []))
        presentationSubmenu.addItem(menuItem("Brief".localized, action: #selector(MainWindowViewController.menuPresentationBrief(_:)), key: "", modifiers: []))
        presentationSubmenu.addItem(menuItem("Gallery".localized, action: #selector(MainWindowViewController.menuPresentationGallery(_:)), key: "", modifiers: []))
        let presentationItem = NSMenuItem(title: "Presentation".localized, action: nil, keyEquivalent: "")
        presentationItem.submenu = presentationSubmenu
        submenu.addItem(presentationItem)
        submenu.addItem(.separator())
        let sortSubmenu = NSMenu(title: "Sort By".localized)
        sortSubmenu.addItem(menuItem("Name".localized, action: #selector(MainWindowViewController.menuSortByName(_:)), command: .sortByName))
        sortSubmenu.addItem(menuItem("Extension".localized, action: #selector(MainWindowViewController.menuSortByExtension(_:)), command: .sortByExtension))
        sortSubmenu.addItem(menuItem("Kind".localized, action: #selector(MainWindowViewController.menuSortByKind(_:)), command: .sortByKind))
        sortSubmenu.addItem(menuItem("Size".localized, action: #selector(MainWindowViewController.menuSortBySize(_:)), command: .sortBySize))
        sortSubmenu.addItem(menuItem("Modified".localized, action: #selector(MainWindowViewController.menuSortByModified(_:)), command: .sortByModified))
        sortSubmenu.addItem(menuItem("Created".localized, action: #selector(MainWindowViewController.menuSortByCreated(_:)), command: .sortByCreated))
        sortSubmenu.addItem(menuItem("Added".localized, action: #selector(MainWindowViewController.menuSortByAdded(_:)), command: .sortByAdded))
        sortSubmenu.addItem(menuItem("Accessed".localized, action: #selector(MainWindowViewController.menuSortByAccessed(_:)), command: .sortByAccessed))
        let sortItem = NSMenuItem(title: "Sort By".localized, action: nil, keyEquivalent: "")
        sortItem.submenu = sortSubmenu
        submenu.addItem(sortItem)

        let orderSubmenu = NSMenu(title: "Sort Direction".localized)
        orderSubmenu.addItem(menuItem("Ascending".localized, action: #selector(MainWindowViewController.menuSortAscending(_:)), command: .sortAscending))
        orderSubmenu.addItem(menuItem("Descending".localized, action: #selector(MainWindowViewController.menuSortDescending(_:)), command: .sortDescending))
        let orderItem = NSMenuItem(title: "Sort Direction".localized, action: nil, keyEquivalent: "")
        orderItem.submenu = orderSubmenu
        submenu.addItem(orderItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Toggle Beta Terminal".localized, action: #selector(MainWindowViewController.menuToggleTerminal(_:)), command: .toggleTerminal))
        submenu.addItem(menuItem("Toggle Single Pane".localized, action: #selector(MainWindowViewController.menuTogglePaneLayout(_:)), command: .togglePaneLayout))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("New Tab".localized, action: #selector(MainWindowViewController.menuNewTab(_:)), command: .newTab))
        submenu.addItem(menuItem("Close Tab".localized, action: #selector(MainWindowViewController.menuCloseTab(_:)), command: .closeTab))
        submenu.addItem(menuItem("Next Tab".localized, action: #selector(MainWindowViewController.menuNextTab(_:)), command: .nextTab))
        submenu.addItem(menuItem("Previous Tab".localized, action: #selector(MainWindowViewController.menuPreviousTab(_:)), command: .previousTab))
        submenu.addItem(menuItem("Toggle Sidebar".localized, action: #selector(MainWindowViewController.menuToggleSidebar(_:)), command: .toggleSidebar))
        item.submenu = submenu
        return item
    }

    private func goMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Go".localized)
        submenu.addItem(menuItem("Back".localized, action: #selector(MainWindowViewController.menuBack(_:)), command: .back))
        submenu.addItem(menuItem("Forward".localized, action: #selector(MainWindowViewController.menuForward(_:)), command: .forward))
        submenu.addItem(menuItem("Parent Folder".localized, action: #selector(MainWindowViewController.menuParent(_:)), command: .parent))
        submenu.addItem(menuItem("Go to Folder…".localized, action: #selector(MainWindowViewController.menuGoToFolder(_:)), command: .goToFolder))
        submenu.addItem(menuItem("Quick Locations…".localized, action: #selector(MainWindowViewController.menuQuickLocations(_:)), command: .quickLocations))
        submenu.addItem(menuItem("Search This Folder…".localized, action: #selector(MainWindowViewController.menuSearchDescendants(_:)), command: .searchDescendants))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Home".localized, action: #selector(MainWindowViewController.menuHome(_:)), command: .home))
        submenu.addItem(menuItem("Downloads".localized, action: #selector(MainWindowViewController.menuDownloads(_:)), command: .downloads))
        submenu.addItem(menuItem("Applications".localized, action: #selector(MainWindowViewController.menuApplications(_:)), command: .applications))
        submenu.addItem(menuItem("Go to Scratch Folder".localized, action: #selector(MainWindowViewController.menuScratchDirectory(_:)), command: .scratchDirectory))
        item.submenu = submenu
        return item
    }

    private func commandMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Command".localized)
        submenu.addItem(menuItem("Switch Pane".localized, action: #selector(MainWindowViewController.menuSwitchPane(_:)), command: .switchPane))
        submenu.addItem(menuItem("Swap Panes".localized, action: #selector(MainWindowViewController.menuSwapPanes(_:)), command: .swapPanes))
        submenu.addItem(menuItem("Sync Opposite Pane".localized, action: #selector(MainWindowViewController.menuSyncOppositePane(_:)), command: .syncOppositePane))
        submenu.addItem(menuItem("Reveal in Opposite Pane".localized, action: #selector(MainWindowViewController.menuRevealInOppositePane(_:)), command: .revealInOppositePane))
        submenu.addItem(menuItem("Follow Symbolic Link".localized, action: #selector(MainWindowViewController.menuFollowSymbolicLink(_:)), command: .followSymbolicLink))
        item.submenu = submenu
        return item
    }

    private func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Window".localized)
        submenu.addItem(menuItem("Minimize".localized, action: #selector(NSWindow.performMiniaturize(_:)), key: "m", modifiers: [.command]))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Show Debug Logs…".localized, action: #selector(MainWindowViewController.menuShowDebugLogs(_:)), key: "", modifiers: []))
        item.submenu = submenu
        NSApplication.shared.windowsMenu = submenu
        return item
    }

    private func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Help".localized)
        let helpItem = NSMenuItem(title: "PulseFiles Help".localized, action: #selector(showHelp(_:)), keyEquivalent: "?")
        helpItem.keyEquivalentModifierMask = [.command]
        helpItem.target = self
        submenu.addItem(helpItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Get Support".localized, action: #selector(openSupport(_:)), key: "", modifiers: []))
        submenu.addItem(menuItem("Privacy Policy".localized, action: #selector(openPrivacyPolicy(_:)), key: "", modifiers: []))
        submenu.addItem(menuItem("Report an Issue".localized, action: #selector(reportIssue(_:)), key: "", modifiers: []))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Export Diagnostics…".localized, action: #selector(MainWindowViewController.menuExportDiagnostics(_:)), command: .exportDiagnostics))
        item.submenu = submenu
        return item
    }


    private var helpShortcutsText: String {
#if DEBUG
        "PulseFiles Help Shortcuts Debug".localized
#else
        "PulseFiles Help Shortcuts".localized
#endif
    }

    @objc private func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "PulseFiles Help".localized
        alert.informativeText = helpShortcutsText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)

        if let window = mainWindowController?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func openSupport(_ sender: Any?) {
        NSWorkspace.shared.open(Self.supportURL)
    }

    @objc private func openPrivacyPolicy(_ sender: Any?) {
        NSWorkspace.shared.open(Self.privacyPolicyURL)
    }

    @objc private func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(Self.issueReportingURL)
    }

    private func menuItem(_ title: String, action: Selector, command: MainCommand) -> NSMenuItem {
        let shortcut = MainCommandShortcutRegistry.descriptor(for: command).menuKeyEquivalent
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.key ?? "")
        item.keyEquivalentModifierMask = shortcut?.modifierFlags ?? []
        item.target = nil
        item.identifier = NSUserInterfaceItemIdentifier(AccessibilityIdentifiers.Command.menuItem(command))
        item.setAccessibilityIdentifier(AccessibilityIdentifiers.Command.menuItem(command))
        return item
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var aboutWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileTypeColorPalette.activeScheme = SettingsService().fileColorScheme
        if let icon = appIcon() {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.mainMenu = buildMainMenu()
        let controller = MainWindowController()
        controller.showWindow(nil)
        mainWindowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() -> NSMenu {
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
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit PulseFiles".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        return item
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        if let existingWindow = aboutWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 430))
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

        let doneButton = NSButton(title: "Done".localized, target: self, action: #selector(closeAbout(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        [iconView, nameLabel, versionLabel, descriptionLabel, doneButton].forEach(contentView.addSubview)

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

            doneButton.topAnchor.constraint(greaterThanOrEqualTo: descriptionLabel.bottomAnchor, constant: 24),
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
        submenu.addItem(menuItem("New File".localized, action: #selector(MainWindowViewController.menuNewFile(_:)), key: "n", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("New Folder".localized, action: #selector(MainWindowViewController.menuNewFolder(_:)), key: "n", modifiers: [.command]))
        submenu.addItem(menuItem("Rename".localized, action: #selector(MainWindowViewController.menuRename(_:)), key: "\r", modifiers: []))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Move to Trash".localized, action: #selector(MainWindowViewController.menuMoveToTrash(_:)), key: "\u{8}", modifiers: [.command]))
        item.submenu = submenu
        return item
    }

    private func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Edit".localized)
        submenu.addItem(menuItem("Copy".localized, action: #selector(MainWindowViewController.menuCopyToClipboard(_:)), key: "c", modifiers: [.command]))
        submenu.addItem(menuItem("Cut".localized, action: #selector(MainWindowViewController.menuCutToClipboard(_:)), key: "x", modifiers: [.command]))
        submenu.addItem(menuItem("Paste".localized, action: #selector(MainWindowViewController.menuPasteFromClipboard(_:)), key: "v", modifiers: [.command]))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Cancel Operation".localized, action: #selector(MainWindowViewController.menuCancelOperation(_:)), key: ".", modifiers: [.command]))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy to Opposite Pane".localized, action: #selector(MainWindowViewController.menuCopy(_:)), key: "", modifiers: []))
        submenu.addItem(menuItem("Move to Opposite Pane".localized, action: #selector(MainWindowViewController.menuMove(_:)), key: "m", modifiers: [.command]))
        item.submenu = submenu
        return item
    }

    private func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "View".localized)
        submenu.addItem(menuItem("Refresh".localized, action: #selector(MainWindowViewController.menuRefresh(_:)), key: "r", modifiers: [.command]))
        submenu.addItem(menuItem("Reveal in Finder".localized, action: #selector(MainWindowViewController.menuReveal(_:)), key: "r", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("Show Hidden Files".localized, action: #selector(MainWindowViewController.menuToggleHiddenFiles(_:)), key: ".", modifiers: [.command, .shift]))
        submenu.addItem(.separator())
        let sortSubmenu = NSMenu(title: "Sort By".localized)
        sortSubmenu.addItem(menuItem("Name".localized, action: #selector(MainWindowViewController.menuSortByName(_:)), key: "", modifiers: []))
        sortSubmenu.addItem(menuItem("Size".localized, action: #selector(MainWindowViewController.menuSortBySize(_:)), key: "", modifiers: []))
        sortSubmenu.addItem(menuItem("Modified".localized, action: #selector(MainWindowViewController.menuSortByModified(_:)), key: "", modifiers: []))
        let sortItem = NSMenuItem(title: "Sort By".localized, action: nil, keyEquivalent: "")
        sortItem.submenu = sortSubmenu
        submenu.addItem(sortItem)

        let orderSubmenu = NSMenu(title: "Sort Direction".localized)
        orderSubmenu.addItem(menuItem("Ascending".localized, action: #selector(MainWindowViewController.menuSortAscending(_:)), key: "", modifiers: []))
        orderSubmenu.addItem(menuItem("Descending".localized, action: #selector(MainWindowViewController.menuSortDescending(_:)), key: "", modifiers: []))
        let orderItem = NSMenuItem(title: "Sort Direction".localized, action: nil, keyEquivalent: "")
        orderItem.submenu = orderSubmenu
        submenu.addItem(orderItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Toggle Terminal".localized, action: #selector(MainWindowViewController.menuToggleTerminal(_:)), key: "`", modifiers: [.command]))
        submenu.addItem(menuItem("Toggle Single Pane".localized, action: #selector(MainWindowViewController.menuTogglePaneLayout(_:)), key: "t", modifiers: [.command]))
        submenu.addItem(menuItem("Toggle Sidebar".localized, action: #selector(MainWindowViewController.menuToggleSidebar(_:)), key: "s", modifiers: [.command, .option]))
        item.submenu = submenu
        return item
    }

    private func goMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Go".localized)
        submenu.addItem(menuItem("Back".localized, action: #selector(MainWindowViewController.menuBack(_:)), key: "[", modifiers: [.command]))
        submenu.addItem(menuItem("Forward".localized, action: #selector(MainWindowViewController.menuForward(_:)), key: "]", modifiers: [.command]))
        submenu.addItem(menuItem("Parent Folder".localized, action: #selector(MainWindowViewController.menuParent(_:)), key: "\u{F700}", modifiers: [.command]))
        submenu.addItem(menuItem("Go to Folder…".localized, action: #selector(MainWindowViewController.menuGoToFolder(_:)), key: "g", modifiers: [.command, .shift]))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Home".localized, action: #selector(MainWindowViewController.menuHome(_:)), key: "h", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("Downloads".localized, action: #selector(MainWindowViewController.menuDownloads(_:)), key: "l", modifiers: [.command, .option]))
        submenu.addItem(menuItem("Applications".localized, action: #selector(MainWindowViewController.menuApplications(_:)), key: "a", modifiers: [.command, .shift]))
        item.submenu = submenu
        return item
    }

    private func commandMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Command".localized)
        submenu.addItem(menuItem("Switch Pane".localized, action: #selector(MainWindowViewController.menuSwitchPane(_:)), key: "\t", modifiers: []))
        submenu.addItem(menuItem("Focus Left Pane".localized, action: #selector(MainWindowViewController.menuFocusLeftPane(_:)), key: "\u{F702}", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("Focus Right Pane".localized, action: #selector(MainWindowViewController.menuFocusRightPane(_:)), key: "\u{F703}", modifiers: [.command, .shift]))
        item.submenu = submenu
        return item
    }

    private func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Window".localized)
        submenu.addItem(menuItem("Minimize".localized, action: #selector(NSWindow.performMiniaturize(_:)), key: "m", modifiers: [.command]))
        item.submenu = submenu
        NSApplication.shared.windowsMenu = submenu
        return item
    }

    private func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Help".localized)
        submenu.addItem(withTitle: "PulseFiles Help".localized, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}

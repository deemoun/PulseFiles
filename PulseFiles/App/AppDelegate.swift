import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        submenu.addItem(withTitle: "About PulseFiles", action: nil, keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit PulseFiles", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        return item
    }

    private func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "File")
        submenu.addItem(menuItem("New File", action: #selector(MainWindowViewController.menuNewFile(_:)), key: "n", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("New Folder", action: #selector(MainWindowViewController.menuNewFolder(_:)), key: "n", modifiers: [.command]))
        submenu.addItem(menuItem("Rename", action: #selector(MainWindowViewController.menuRename(_:)), key: "\r", modifiers: []))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Move to Trash", action: #selector(MainWindowViewController.menuMoveToTrash(_:)), key: "\u{8}", modifiers: [.command]))
        item.submenu = submenu
        return item
    }

    private func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Edit")
        submenu.addItem(menuItem("Copy to Opposite Pane", action: #selector(MainWindowViewController.menuCopy(_:)), key: "c", modifiers: [.command]))
        submenu.addItem(menuItem("Move to Opposite Pane", action: #selector(MainWindowViewController.menuMove(_:)), key: "m", modifiers: [.command]))
        item.submenu = submenu
        return item
    }

    private func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "View")
        submenu.addItem(menuItem("Refresh", action: #selector(MainWindowViewController.menuRefresh(_:)), key: "r", modifiers: [.command]))
        submenu.addItem(menuItem("Show Hidden Files", action: #selector(MainWindowViewController.menuToggleHiddenFiles(_:)), key: ".", modifiers: [.command, .shift]))
        submenu.addItem(.separator())
        let sortSubmenu = NSMenu(title: "Sort By")
        sortSubmenu.addItem(menuItem("Name", action: #selector(MainWindowViewController.menuSortByName(_:)), key: "", modifiers: []))
        sortSubmenu.addItem(menuItem("Size", action: #selector(MainWindowViewController.menuSortBySize(_:)), key: "", modifiers: []))
        sortSubmenu.addItem(menuItem("Modified", action: #selector(MainWindowViewController.menuSortByModified(_:)), key: "", modifiers: []))
        let sortItem = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        sortItem.submenu = sortSubmenu
        submenu.addItem(sortItem)

        let orderSubmenu = NSMenu(title: "Sort Direction")
        orderSubmenu.addItem(menuItem("Ascending", action: #selector(MainWindowViewController.menuSortAscending(_:)), key: "", modifiers: []))
        orderSubmenu.addItem(menuItem("Descending", action: #selector(MainWindowViewController.menuSortDescending(_:)), key: "", modifiers: []))
        let orderItem = NSMenuItem(title: "Sort Direction", action: nil, keyEquivalent: "")
        orderItem.submenu = orderSubmenu
        submenu.addItem(orderItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Toggle Terminal", action: #selector(MainWindowViewController.menuToggleTerminal(_:)), key: "`", modifiers: [.command]))
        submenu.addItem(menuItem("Toggle Sidebar", action: #selector(MainWindowViewController.menuToggleSidebar(_:)), key: "s", modifiers: [.command, .option]))
        item.submenu = submenu
        return item
    }

    private func goMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Go")
        submenu.addItem(menuItem("Back", action: #selector(MainWindowViewController.menuBack(_:)), key: "[", modifiers: [.command]))
        submenu.addItem(menuItem("Forward", action: #selector(MainWindowViewController.menuForward(_:)), key: "]", modifiers: [.command]))
        submenu.addItem(menuItem("Parent Folder", action: #selector(MainWindowViewController.menuParent(_:)), key: "\u{F700}", modifiers: [.command]))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Home", action: #selector(MainWindowViewController.menuHome(_:)), key: "h", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("Downloads", action: #selector(MainWindowViewController.menuDownloads(_:)), key: "l", modifiers: [.command, .option]))
        submenu.addItem(menuItem("Applications", action: #selector(MainWindowViewController.menuApplications(_:)), key: "a", modifiers: [.command, .shift]))
        item.submenu = submenu
        return item
    }

    private func commandMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Command")
        submenu.addItem(menuItem("Switch Pane", action: #selector(MainWindowViewController.menuSwitchPane(_:)), key: "\t", modifiers: []))
        submenu.addItem(menuItem("Focus Left Pane", action: #selector(MainWindowViewController.menuFocusLeftPane(_:)), key: "\u{F702}", modifiers: [.command, .shift]))
        submenu.addItem(menuItem("Focus Right Pane", action: #selector(MainWindowViewController.menuFocusRightPane(_:)), key: "\u{F703}", modifiers: [.command, .shift]))
        item.submenu = submenu
        return item
    }

    private func windowMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Window")
        submenu.addItem(menuItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", modifiers: [.command]))
        item.submenu = submenu
        NSApplication.shared.windowsMenu = submenu
        return item
    }

    private func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "Help")
        submenu.addItem(withTitle: "PulseFiles Help", action: nil, keyEquivalent: "")
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

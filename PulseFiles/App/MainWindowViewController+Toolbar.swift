// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

extension MainWindowViewController {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .search, .toggleTerminal, .toggleSidebar, .viewOptions, .settings]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search".localized
            item.searchField.placeholderString = "Search active pane".localized
            item.searchField.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.searchField)
            item.searchField.target = self
            item.searchField.action = #selector(toolbarSearchChanged(_:))
            item.searchField.sendsSearchStringImmediately = true
            toolbarSearchField = item.searchField
            return item
        case .toggleTerminal:
            let item = toolbarItem(itemIdentifier, label: "Beta Terminal".localized, symbol: "terminal", action: #selector(toolbarToggleTerminal(_:)))
            item.view?.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.terminalToggle)
            return item
        case .toggleSidebar:
            let item = toolbarItem(itemIdentifier, label: "Sidebar".localized, symbol: "sidebar.right", action: #selector(toolbarToggleSidebar(_:)))
            item.view?.setAccessibilityIdentifier(AccessibilityIdentifiers.Toolbar.sidebarToggle)
            sidebarToolbarItem = item
            updateSidebarToolbarItem()
            return item
        case .viewOptions:
            return toolbarItem(itemIdentifier, label: "View".localized, symbol: "line.3.horizontal.decrease.circle", action: #selector(toolbarViewOptions(_:)))
        case .settings:
            return toolbarItem(itemIdentifier, label: "Settings".localized, symbol: "gearshape", action: #selector(toolbarSettings(_:)))
        default:
            return nil
        }
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .toggleSidebar {
            updateSidebarToolbarItem()
        }
        return true
    }

    @objc private func toolbarBack(_ sender: Any?) {
        performCommand(.back, entrySurface: .toolbar)
    }

    @objc private func toolbarForward(_ sender: Any?) {
        performCommand(.forward, entrySurface: .toolbar)
    }

    @objc private func toolbarToggleTerminal(_ sender: Any?) {
        performCommand(.toggleTerminal, entrySurface: .toolbar)
    }

    @objc private func toolbarToggleSidebar(_ sender: Any?) {
        performCommand(.toggleSidebar, entrySurface: .toolbar)
    }

    @objc func toolbarSettings(_ sender: Any?) {
        presentSettings(sender)
    }
}

private extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("PulseFilesToolbarBack")
    static let forward = NSToolbarItem.Identifier("PulseFilesToolbarForward")
    static let search = NSToolbarItem.Identifier("PulseFilesToolbarSearch")
    static let toggleTerminal = NSToolbarItem.Identifier("PulseFilesToolbarTerminal")
    static let toggleSidebar = NSToolbarItem.Identifier("PulseFilesToolbarSidebar")
    static let viewOptions = NSToolbarItem.Identifier("PulseFilesToolbarViewOptions")
    static let settings = NSToolbarItem.Identifier("PulseFilesToolbarSettings")
}

extension MainWindowViewController: NSToolbarDelegate, NSToolbarItemValidation {}

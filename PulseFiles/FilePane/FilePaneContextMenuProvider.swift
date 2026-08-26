// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Builds pane context menus while leaving selection/focus ownership in `FilePaneViewController`.
@MainActor
package final class FilePaneContextMenuProvider: NSObject {
    enum Context { case parent, item(FileItem, hasOppositePane: Bool), background(showsHiddenFiles: Bool) }
    struct Entry: Equatable { let title: String; let command: MainCommand?; let separator: Bool }
    package var onCommand: ((MainCommand) -> Void)?
    package var onOpenWithApplication: ((URL, URL?) -> Void)?
    private let openWithApplicationResolver: OpenWithMenuApplicationResolver

    package init(openWithApplicationResolver: OpenWithMenuApplicationResolver? = nil) {
        self.openWithApplicationResolver = openWithApplicationResolver ?? OpenWithMenuApplicationResolver()
    }

    package static func entries(for context: Context) -> [Entry] {
        func item(_ title: String, _ command: MainCommand) -> Entry { Entry(title: title.localized, command: command, separator: false) }
        let separator = Entry(title: "", command: nil, separator: true)
        switch context {
        case .parent: return [item("Open Parent Folder", .parent)]
        case let .item(file, opposite):
            var result = [item("Open", .open)]
            if !file.isDirectory { result.append(item("Open With…", .openWith)) }
            result += [item("Rename", .rename), item("Duplicate", .duplicate), item("Get Info", .getInfo), separator,
                       item("Select Same Extension", .selectSameExtension), item("Deselect Same Extension", .deselectSameExtension)]
            if opposite { result += [separator, item("Copy to Opposite Pane", .copy), item("Move to Opposite Pane", .move), item("Reveal in Opposite Pane", .revealInOppositePane)] }
            if file.isSymbolicLink { result.append(item("Follow Symbolic Link", .followSymbolicLink)) }
            result += [separator, item("Reveal in Finder", .reveal), item("Delete", .trash)]
            return result
        case let .background(hidden):
            return [item("New File", .newFile), item("New Folder", .newFolder), separator, item("Refresh", .refresh),
                    item("Select All", .selectAll), item("Deselect All", .deselectAll), item("Select by Pattern…", .selectByPattern),
                    item("Deselect by Pattern…", .deselectByPattern), item("Invert Selection", .invertSelection),
                    item(hidden ? "Hide Hidden Files" : "Show Hidden Files", .toggleHiddenFiles)]
        }
    }

    package func menu(for context: Context) -> NSMenu {
        let menu = NSMenu(title: "File")
        for entry in Self.entries(for: context) {
            if entry.separator { menu.addItem(.separator()); continue }
            let menuItem = NSMenuItem(title: entry.title, action: #selector(performCommand(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = entry.command.map(CommandBox.init)
            menuItem.setAccessibilityLabel(entry.title)
            if let command = entry.command {
                let identifier = AccessibilityIdentifiers.Command.menuItem(command)
                menuItem.identifier = NSUserInterfaceItemIdentifier(identifier)
                menuItem.setAccessibilityIdentifier(identifier)
            }
            menu.addItem(menuItem)
        }
        if case let .item(file, _) = context, !file.isDirectory,
           let openWithItem = menu.items.first(where: { ($0.representedObject as? CommandBox)?.command == .openWith }) {
            configureOpenWithSubmenu(for: file.url, menuItem: openWithItem)
        }
        return menu
    }

    private func configureOpenWithSubmenu(for url: URL, menuItem: NSMenuItem) {
        let submenu = NSMenu(title: "Open With")
        let defaultItem = NSMenuItem(title: "Default Application", action: #selector(openWithDefault(_:)), keyEquivalent: "")
        defaultItem.target = self; defaultItem.representedObject = url; submenu.addItem(defaultItem)
        let loading = NSMenuItem(title: "Loading Applications…", action: nil, keyEquivalent: "")
        loading.isEnabled = false; submenu.addItem(loading); menuItem.submenu = submenu
        openWithApplicationResolver.resolveApplications(for: url, menuItem: menuItem, submenu: submenu, loadingItem: loading) { [weak self] appURL in
            let item = NSMenuItem(title: appURL.deletingPathExtension().lastPathComponent, action: #selector(FilePaneContextMenuProvider.openWithApplication(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = OpenWithRequest(fileURL: url, applicationURL: appURL); return item
        }
    }

    @objc private func openWithDefault(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }; onOpenWithApplication?(url, nil)
    }
    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? OpenWithRequest else { return }
        onOpenWithApplication?(request.fileURL, request.applicationURL)
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? CommandBox)?.command else { return }
        onCommand?(command)
    }

    private final class CommandBox: NSObject {
        let command: MainCommand
        init(_ command: MainCommand) { self.command = command }
    }
}

/// Carries an Open With selection without coupling menu construction to filesystem operations.
package final class OpenWithRequest {
    package let fileURL: URL
    package let applicationURL: URL
    package init(fileURL: URL, applicationURL: URL) { self.fileURL = fileURL; self.applicationURL = applicationURL }
}

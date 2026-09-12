// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class SelectionInformationUIAdapter {
    private let window: () -> NSWindow?

    init(window: @escaping () -> NSWindow?) { self.window = window }

    func presentInformation(name: String, path: String, isDirectory: Bool, size: Int64, modificationDate: Date?) {
        let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        let modified = modificationDate.map {
            DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
        } ?? "Unknown".localized
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "Location: %@\nKind: %@\nSize: %@\nModified: %@".localized(
            with: path, isDirectory ? "Folder".localized : "File".localized, formattedSize, modified
        )
        alert.addButton(withTitle: "OK".localized)
        present(alert) { _ in }
    }

    func confirmDelete(urls: [URL], permanently: Bool, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Self.deleteMessage(permanently: permanently, itemCount: urls.count)
        alert.informativeText = Self.deleteDetail(permanently: permanently, urls: urls)
        alert.addButton(withTitle: permanently ? "Permanently Delete".localized : "Move to Trash".localized)
        alert.addButton(withTitle: "Cancel — Keep Items".localized)
        present(alert) { if $0 == .alertFirstButtonReturn { completion() } }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = window() { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }

    static func deleteMessage(permanently: Bool, itemCount: Int) -> String {
        let label = itemCount == 1 ? "1 Item".localized : "%d Items".localized(with: itemCount)
        return permanently ? "Permanently Delete %@?".localized(with: label) : "Move %@ to Trash?".localized(with: label)
    }

    static func deleteDetail(permanently: Bool, urls: [URL]) -> String {
        var lines = [
            "Operation: %@".localized(with: permanently ? "Permanent Delete".localized : "Move to Trash".localized),
            permanently
                ? "This permanently deletes the selected item(s) immediately. This cannot be undone from the Trash.".localized
                : "This moves the selected item(s) to the macOS Trash. You can restore them from the Trash until it is emptied.".localized,
            "", "Items:".localized
        ]
        let names = urls.prefix(8).map { "- \($0.lastPathComponent)" }
        lines.append(contentsOf: names)
        if urls.count > names.count { lines.append("- ...and %d more".localized(with: urls.count - names.count)) }
        return lines.joined(separator: "\n")
    }
}

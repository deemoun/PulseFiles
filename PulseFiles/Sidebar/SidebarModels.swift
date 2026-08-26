// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

package struct SidebarItem {
    package let title: String
    package let subtitle: String?
    package let url: URL
    package let symbol: String
    package let group: String
    package let badge: Int?
    package let isAvailable: Bool

    package init(title: String, subtitle: String? = nil, url: URL, symbol: String, group: String, badge: Int? = nil, isAvailable: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.symbol = symbol
        self.group = group
        self.badge = badge
        self.isAvailable = isAvailable
    }
}

package struct SidebarInfoRow {
    package let title: String
    package let value: String
    package let symbol: String
}

package struct SelectionInspectorPresentation {
    package let title: String
    package let subtitle: String
    package let icon: NSImage
    package let rows: [SidebarInfoRow]
    package let selectedURLs: [URL]

    @MainActor
    package static func make(for items: [FileItem]) -> SelectionInspectorPresentation? {
        guard !items.isEmpty else { return nil }
        if items.count == 1, let item = items.first {
            return SelectionInspectorPresentation(
                title: item.displayName,
                subtitle: displayPath(for: item.url),
                icon: FileIconProvider.shared.image(for: item.iconKey),
                rows: singleSelectionRows(for: item),
                selectedURLs: [item.url]
            )
        }

        let totalSize = items.reduce(Int64(0)) { $0 + $1.size }
        let folderCount = items.filter(\.isDirectory).count
        let fileCount = items.count - folderCount
        return SelectionInspectorPresentation(
            title: "\(items.count) items selected",
            subtitle: selectionBreakdown(fileCount: fileCount, folderCount: folderCount),
            icon: NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil) ?? NSImage(),
            rows: [
                SidebarInfoRow(title: "Selected Items", value: "\(items.count)", symbol: "number"),
                SidebarInfoRow(title: "Selected Size", value: FileSizeFormatter.string(fromByteCount: totalSize), symbol: "doc.on.doc"),
                SidebarInfoRow(title: "Total Space", value: "Calculating…", symbol: "externaldrive"),
                SidebarInfoRow(title: "Type", value: "Mixed selection", symbol: "tag")
            ],
            selectedURLs: items.map(\.url)
        )
    }

    private static func singleSelectionRows(for item: FileItem) -> [SidebarInfoRow] {
        var rows = [
            SidebarInfoRow(title: "Total Space", value: "Calculating…", symbol: "externaldrive"),
            SidebarInfoRow(title: "File Size", value: item.isDirectory ? "Folder" : FileSizeFormatter.string(fromByteCount: item.size), symbol: "doc.text"),
            SidebarInfoRow(title: "Type", value: item.fileType.displayName, symbol: item.isDirectory ? "folder" : "tag"),
            SidebarInfoRow(title: "Localized Type", value: item.localizedTypeDescription, symbol: "text.badge.checkmark")
        ]
        rows.append(SidebarInfoRow(title: "Created", value: formattedDate(item.creationDate), symbol: "calendar.badge.plus"))
        rows.append(SidebarInfoRow(title: "Modified", value: formattedDate(item.modificationDate), symbol: "calendar"))
        rows.append(SidebarInfoRow(title: "Permissions", value: formattedPermissions(item.posixPermissions), symbol: "lock.shield"))
        rows.append(SidebarInfoRow(title: "Owner", value: nonEmpty(item.owner), symbol: "person"))
        rows.append(SidebarInfoRow(title: "Group", value: nonEmpty(item.group), symbol: "person.2"))
        return rows
    }

    private static func selectionBreakdown(fileCount: Int, folderCount: Int) -> String {
        [pluralized(fileCount, singular: "file"), pluralized(folderCount, singular: "folder")]
            .filter { !$0.hasPrefix("0 ") }
            .joined(separator: ", ")
    }

    private static func pluralized(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return dateFormatter.string(from: date)
    }

    private static func formattedPermissions(_ permissions: Int?) -> String {
        guard let permissions else { return "Unknown" }
        return String(format: "%03o", permissions & 0o777)
    }

    private static func nonEmpty(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Unknown" }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func displayPath(for url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}


extension FileItemType {
    package var displayName: String {
        switch self {
        case .folder: return "Folder"
        case .symbolicLink: return "Symbolic Link"
        case .package: return "Package"
        case .file: return "File"
        case .unknown: return "Unknown"
        }
    }
}

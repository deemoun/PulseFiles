// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesUtilities

package final class BreadcrumbView: NSStackView {
    package var onSelect: ((URL) -> Void)?
    private(set) var url: URL = FileManager.default.homeDirectoryForCurrentUser
    private var componentURLs: [URL] = []

    package init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 4
        alignment = .centerY
    }

    required init?(coder: NSCoder) {
        nil
    }

    package func configure(url: URL) {
        self.url = url
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        // macOS may return protected paths such as /.nofollow/Users/… .
        // Hide only the root namespace marker in the presentation, while
        // retaining that namespace in every navigation target. A literal
        // /.nofollow stub (without a trailing slash) remains visible.
        let components = url.pathComponents
        let hasProtectedRoot = PathUtilities.hasProtectedRootNamespace(url)
        let indices = Array(components.indices.dropFirst(hasProtectedRoot ? 1 : 0))
        componentURLs = []
        for (index, componentIndex) in indices.enumerated() {
            var target = url
            for _ in (componentIndex + 1)..<components.count {
                target.deleteLastPathComponent()
            }
            componentURLs.append(target)
            let title = index == 0 ? "/" : components[componentIndex]
            let button = NSButton(title: title, target: self, action: #selector(selectComponent(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.tag = index
            button.setAccessibilityLabel("Open \(title)")
            addArrangedSubview(button)
            if index < indices.count - 1 {
                let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
                chevron.symbolConfiguration = .init(pointSize: 10, weight: .regular)
                addArrangedSubview(chevron)
            }
        }
    }

    @objc private func selectComponent(_ sender: NSButton) {
        guard componentURLs.indices.contains(sender.tag) else { return }
        onSelect?(componentURLs[sender.tag])
    }
}

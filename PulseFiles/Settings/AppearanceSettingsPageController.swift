// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
package final class AppearanceSettingsPageController: SettingsPageControllerBase {
    private let settings: AppearanceSettingsProviding
    private let liquidGlass = NSButton(checkboxWithTitle: "Enable liquid glass interface".localized, target: nil, action: nil)
    private let sidebar = NSButton(checkboxWithTitle: "Show sidebar by default".localized, target: nil, action: nil)
    private let singlePane = NSButton(checkboxWithTitle: "Use single pane by default".localized, target: nil, action: nil)
    private let widthSlider = NSSlider(value: 260, minValue: 220, maxValue: 340, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "260 pt")
    private var wells: [FileVisualCategory: NSColorWell] = [:]

    package init(settings: AppearanceSettingsProviding) {
        self.settings = settings
        super.init()
        [liquidGlass, sidebar, singlePane].forEach { $0.target = self; $0.action = #selector(changed(_:)) }
        widthSlider.target = self; widthSlider.action = #selector(changed(_:))
        liquidGlass.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.liquidGlass)
        sidebar.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.sidebarVisible)
        singlePane.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.singlePane)
        widthSlider.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.sidebarWidth)
        install(sections: [section(title: "Appearance & Layout".localized, views: [sidebar, liquidGlass, singlePane, widthRow()]), paletteView()])
        reloadFromSettings()
    }

    package override func reloadFromSettings() {
        liquidGlass.state = settings.liquidGlassEnabled ? .on : .off
        sidebar.state = settings.defaultSidebarVisible ? .on : .off
        singlePane.state = settings.defaultSinglePaneMode ? .on : .off
        widthSlider.doubleValue = settings.preferredSidebarWidth
        widthLabel.stringValue = "%d pt".localized(with: Int(settings.preferredSidebarWidth))
        FileVisualCategory.allCases.forEach { wells[$0]?.color = settings.fileColorScheme.color(for: $0) }
    }

    private func widthRow() -> NSView {
        widthLabel.alignment = .right
        let row = NSStackView(views: [NSTextField(labelWithString: "Sidebar width".localized), widthSlider, widthLabel])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        widthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        return row
    }

    private func paletteView() -> NSView {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 14
        for (index, category) in FileVisualCategory.allCases.enumerated() {
            let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
            well.target = self; well.action = #selector(colorChanged(_:)); well.tag = index
            well.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.fileColor(category))
            wells[category] = well
            let description = NSTextField(wrappingLabelWithString: category.settingsDescription); description.textColor = .secondaryLabelColor
            let text = NSStackView(views: [NSTextField(labelWithString: category.displayName), description]); text.orientation = .vertical; text.alignment = .leading
            let row = NSStackView(views: [well, text]); row.orientation = .horizontal; row.alignment = .top; row.spacing = 14
            rows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        let reset = NSButton(title: "Reset Palette".localized, target: self, action: #selector(resetPalette(_:)))
        reset.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.resetPalette)
        return section(title: "File color palette".localized, views: [rows, reset])
    }

    @objc private func changed(_ sender: Any?) {
        settings.liquidGlassEnabled = liquidGlass.state == .on
        settings.defaultSidebarVisible = sidebar.state == .on
        settings.defaultSinglePaneMode = singlePane.state == .on
        settings.preferredSidebarWidth = widthSlider.doubleValue
        reloadFromSettings(); onChange?()
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard FileVisualCategory.allCases.indices.contains(sender.tag) else { return }
        var colors = settings.fileColorScheme.colors
        colors[FileVisualCategory.allCases[sender.tag]] = sender.color
        settings.fileColorScheme = FileColorScheme(colors: colors)
        FileTypeColorPalette.activeScheme = settings.fileColorScheme
        onChange?()
    }

    @objc private func resetPalette(_ sender: Any?) {
        settings.resetFileColorScheme(); FileTypeColorPalette.activeScheme = settings.fileColorScheme
        reloadFromSettings(); onChange?()
    }
}

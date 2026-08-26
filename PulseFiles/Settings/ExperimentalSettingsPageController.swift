// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
package final class ExperimentalSettingsPageController: SettingsPageControllerBase {
    private let settings: ExperimentalSettingsProviding
    private let terminalEnabled = NSButton(checkboxWithTitle: "Enable Beta Terminal".localized, target: nil, action: nil)
    private let terminalVisible = NSButton(checkboxWithTitle: "Show Beta Terminal by default".localized, target: nil, action: nil)
#if DEBUG
    private let sandbox = NSButton(checkboxWithTitle: "Restrict browsing and file operations to the experimental sandbox".localized, target: nil, action: nil)
#endif
    package init(settings: ExperimentalSettingsProviding) {
        self.settings = settings; super.init()
        var controls = [terminalEnabled, terminalVisible]
#if DEBUG
        controls.append(sandbox)
#endif
        controls.forEach { $0.target = self; $0.action = #selector(changed(_:)) }
        terminalEnabled.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.terminalEnabled)
        terminalVisible.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.terminalVisible)
#if DEBUG
        sandbox.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.experimentalSandbox)
#endif
        reloadFromSettings()
    }
    package override func reloadFromSettings() {
        terminalEnabled.state = settings.experimentalTerminalEnabled ? .on : .off
        terminalVisible.state = settings.defaultTerminalVisible ? .on : .off
        terminalVisible.isEnabled = settings.experimentalTerminalEnabled
        let warning = NSTextField(wrappingLabelWithString: settings.experimentalTerminalEnabled ? "Beta Terminal is enabled. Shell commands can modify or delete files in the active pane folder.".localized : "Beta Terminal is disabled and hidden. Enable it only if you accept that shell commands can modify or delete files.".localized); warning.textColor = .secondaryLabelColor
        var sections = [section(title: "Beta Terminal".localized, views: [terminalEnabled, terminalVisible, warning])]
#if DEBUG
        sandbox.state = settings.experimentalSandboxEnabled ? .on : .off
        sections.append(section(title: "Experimental Sandbox".localized, views: [sandbox]))
#endif
        install(sections: sections)
    }
    @objc private func changed(_ sender: Any?) {
        settings.experimentalTerminalEnabled = terminalEnabled.state == .on
        settings.defaultTerminalVisible = settings.experimentalTerminalEnabled && terminalVisible.state == .on
#if DEBUG
        settings.experimentalSandboxEnabled = sandbox.state == .on
        ExperimentalFlags.ensureAppSandboxRootExists()
#endif
        reloadFromSettings(); onChange?()
    }
}

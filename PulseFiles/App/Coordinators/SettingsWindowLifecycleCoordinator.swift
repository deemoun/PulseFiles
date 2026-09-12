// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns settings import, propagation ordering, and the single settings-window route.
/// Its boundaries intentionally expose actions rather than the main-window controller.
@MainActor
final class SettingsWindowLifecycleCoordinator {
    struct Actions {
        let importJSONIfChanged: () -> Void
        let applyChanges: () -> Void
        let reloadVisibleSettings: () -> Void
        let makeSettingsController: () -> SettingsViewController
        let show: (SettingsViewController, Any?) -> Void
    }

    private let actions: Actions

    init(actions: Actions) { self.actions = actions }

    func reloadFromJSON() {
        actions.importJSONIfChanged()
        actions.applyChanges()
        actions.reloadVisibleSettings()
    }

    func present(sender: Any?) {
        reloadFromJSON()
        actions.show(actions.makeSettingsController(), sender)
    }
}

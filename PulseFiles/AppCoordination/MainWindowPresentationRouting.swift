// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels

/// AppKit-free description of which pane views belong in the pane split view.
package struct PaneArrangementRoute: Equatable, Sendable {
    package let visiblePanes: [PaneID]
    package let hasOppositePane: Bool

    package init(singlePane: Bool, focusedPane: PaneID) {
        visiblePanes = singlePane ? [focusedPane] : [.left, .right]
        hasOppositePane = !singlePane
    }
}

/// Value-only routing for a potentially destructive delete request.
public enum DeletePromptRoute: Equatable, Sendable {
    case nothingSelected
    case performImmediately(permanently: Bool)
    case confirm(permanently: Bool)

    public static func resolve(itemCount: Int, permanently: Bool, confirmsTrash: Bool) -> Self {
        guard itemCount > 0 else { return .nothingSelected }
        if !permanently && !confirmsTrash { return .performImmediately(permanently: false) }
        return .confirm(permanently: permanently)
    }
}

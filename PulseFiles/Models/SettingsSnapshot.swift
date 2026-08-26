// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A platform-neutral representation of every durable PulseFiles preference.
/// Presentation-only types (notably `NSColor`) must never cross this boundary.
package struct SettingsSnapshot: Codable, Equatable {
    package var appLanguage: String?
    package var defaultSidebarVisible: Bool?
    package var liquidGlassEnabled: Bool?
    package var experimentalTerminalEnabled: Bool?
    package var hasAcknowledgedTerminalWarning: Bool?
    package var defaultTerminalVisible: Bool?
    package var defaultSinglePaneMode: Bool?
    package var showHiddenFilesByDefault: Bool?
    package var defaultPanePresentationMode: PanePresentationMode?
    package var leftPanePresentationMode: PanePresentationMode?
    package var rightPanePresentationMode: PanePresentationMode?
    package var quickSearchMatchMode: QuickSearchMatchMode?
    package var quickSearchPresentation: QuickSearchPresentation?
    package var confirmCopyOperations: Bool?
    package var confirmMoveOperations: Bool?
    package var confirmDeleteOperations: Bool?
    package var permanentlyDeleteInsteadOfTrash: Bool?
    package var experimentalSandboxEnabled: Bool?
    package var preferredSidebarWidth: Double?
    package var lastLeftDirectory: String?
    package var lastRightDirectory: String?
    package var startupLeftDirectory: String?
    package var startupRightDirectory: String?
    package var scratchDirectory: String?
    package var scratchDirectoryIdentity: String?
    package var scratchDirectoryResolvedPath: String?
    package var defaultSortDescriptor: FileSortDescriptor?
    package var leftPaneSortDescriptor: FileSortDescriptor?
    package var rightPaneSortDescriptor: FileSortDescriptor?
    package var leftPaneTabRestoration: PaneRestorationState?
    package var rightPaneTabRestoration: PaneRestorationState?
    package var fileColorScheme: [String: RGBAColor]?

    package init() {}
}

package struct RGBAColor: Codable, Equatable {
    package let red: Double
    package let green: Double
    package let blue: Double
    package let alpha: Double

    package init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

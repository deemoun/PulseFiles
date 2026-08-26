// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
import PulseFilesWorkflows

package enum AccessibilityIdentifiers {
    package enum Pane {
        package static let left = "pulsefiles.pane.left"
        package static let right = "pulsefiles.pane.right"
        package static let leftActiveIndicator = "pulsefiles.pane.left.activeIndicator"
        package static let rightActiveIndicator = "pulsefiles.pane.right.activeIndicator"
        package static let leftTable = "pulsefiles.pane.left.table"
        package static let rightTable = "pulsefiles.pane.right.table"
        package static let leftBreadcrumb = "pulsefiles.pane.left.breadcrumb"
        package static let rightBreadcrumb = "pulsefiles.pane.right.breadcrumb"
        package static let leftContentOverlay = "pulsefiles.pane.left.contentOverlay"
        package static let rightContentOverlay = "pulsefiles.pane.right.contentOverlay"
        package static let leftContentOverlayTitle = "pulsefiles.pane.left.contentOverlay.title"
        package static let rightContentOverlayTitle = "pulsefiles.pane.right.contentOverlay.title"
        package static let leftLoadingIndicator = "pulsefiles.pane.left.contentOverlay.loadingIndicator"
        package static let rightLoadingIndicator = "pulsefiles.pane.right.contentOverlay.loadingIndicator"

        package static func container(for paneID: PaneID) -> String {
            paneID == .left ? left : right
        }

        package static func activeIndicator(for paneID: PaneID) -> String {
            paneID == .left ? leftActiveIndicator : rightActiveIndicator
        }

        package static func table(for paneID: PaneID) -> String {
            paneID == .left ? leftTable : rightTable
        }

        package static func breadcrumb(for paneID: PaneID) -> String {
            paneID == .left ? leftBreadcrumb : rightBreadcrumb
        }

        package static func contentOverlay(for paneID: PaneID) -> String {
            paneID == .left ? leftContentOverlay : rightContentOverlay
        }

        package static func contentOverlayTitle(for paneID: PaneID) -> String {
            paneID == .left ? leftContentOverlayTitle : rightContentOverlayTitle
        }

        package static func loadingIndicator(for paneID: PaneID) -> String {
            paneID == .left ? leftLoadingIndicator : rightLoadingIndicator
        }

        package static func contentOverlayAction(for paneID: PaneID, index: Int) -> String {
            "\(contentOverlay(for: paneID)).action.\(index)"
        }
    }

    package enum Toolbar {
        package static let searchField = "pulsefiles.toolbar.searchField"
        package static let sidebarToggle = "pulsefiles.toolbar.sidebarToggle"
        package static let terminalToggle = "pulsefiles.toolbar.terminalToggle"
    }

    package enum Sidebar {
        package static let panel = "pulsefiles.sidebar.panel"
        package static let list = "pulsefiles.sidebar.list"
        package static let scratchFolder = "pulsefiles.sidebar.scratchFolder"
    }

    package enum Settings {
        package static let categoryControl = "pulsefiles.settings.categories"
        package static let pageHost = "pulsefiles.settings.pageHost"
        package static let done = "pulsefiles.settings.done"
        package static let languageSelector = "pulsefiles.settings.language.selector"
        package static let confirmCopy = "pulsefiles.settings.operations.confirmCopy"
        package static let confirmMove = "pulsefiles.settings.operations.confirmMove"
        package static let confirmDelete = "pulsefiles.settings.operations.confirmDelete"
        package static let permanentDelete = "pulsefiles.settings.operations.permanentDelete"
        package static let clearIncompleteTransfers = "pulsefiles.settings.operations.clearIncompleteTransfers"
        package static let liquidGlass = "pulsefiles.settings.appearance.liquidGlass"
        package static let sidebarVisible = "pulsefiles.settings.appearance.sidebarVisible"
        package static let singlePane = "pulsefiles.settings.appearance.singlePane"
        package static let sidebarWidth = "pulsefiles.settings.appearance.sidebarWidth"
        package static let resetPalette = "pulsefiles.settings.appearance.resetPalette"
        package static let hiddenFiles = "pulsefiles.settings.navigation.hiddenFiles"
        package static let quickSearchMatch = "pulsefiles.settings.navigation.quickSearchMatch"
        package static let quickSearchPresentation = "pulsefiles.settings.navigation.quickSearchPresentation"
        package static let grantFolderAccess = "pulsefiles.settings.access.grantFolder"
        package static let terminalEnabled = "pulsefiles.settings.experimental.terminalEnabled"
        package static let terminalVisible = "pulsefiles.settings.experimental.terminalVisible"
        package static let experimentalSandbox = "pulsefiles.settings.experimental.sandbox"
        package static func fileColor(_ category: FileVisualCategory) -> String { "pulsefiles.settings.appearance.color.\(category)" }
        package static let scratchPath = "pulsefiles.settings.scratchFolder.path"
        package static let chooseScratchFolder = "pulsefiles.settings.scratchFolder.choose"
        package static let openScratchFolder = "pulsefiles.settings.scratchFolder.open"
        package static let clearScratchFolder = "pulsefiles.settings.scratchFolder.clear"
    }

    package enum CommandBar {
        package static let panel = "pulsefiles.commandBar.panel"
        package static let list = "pulsefiles.commandBar.list"
        package static let field = "pulsefiles.commandBar.field"
    }

    package enum QuickLocations {
        package static let popover = "pulsefiles.quickLocations.popover"
        package static let search = "pulsefiles.quickLocations.search"
        package static let list = "pulsefiles.quickLocations.list"
        package static func entry(_ id: String) -> String { "pulsefiles.quickLocations.entry.\(id)" }
    }

    package enum Command {
        package static func menuItem(_ command: MainCommand) -> String {
            "pulsefiles.command.\(String(describing: command))"
        }
    }

    package enum Pattern {
        package static let patternField = "pulsefiles.pattern.field"
        package static let mode = "pulsefiles.pattern.mode"
        package static let matchCount = "pulsefiles.pattern.matchCount"
        package static let apply = "pulsefiles.pattern.apply"
        package static let cancel = "pulsefiles.pattern.cancel"
    }

    package enum FileOperationProgress {
        package static let dialog = "pulsefiles.fileOperationProgress.dialog"
        package static let indicator = "pulsefiles.fileOperationProgress.indicator"
        package static let currentItemLabel = "pulsefiles.fileOperationProgress.currentItem"
        package static let detailLabel = "pulsefiles.fileOperationProgress.detail"
        package static let cancelButton = "pulsefiles.fileOperationProgress.cancel"
    }

    package enum Terminal {
        package static let panel = "pulsefiles.terminal.panel"
        package static let textView = "pulsefiles.terminal.textView"
    }
}

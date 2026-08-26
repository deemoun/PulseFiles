// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import PulseFilesServices
import Foundation

package enum MainCommandEntrySurface: CaseIterable {
    case menu
    case toolbar
    case keyboard
    case commandBar
    case contextMenu
    case paneCallback
}

package struct MainCommandRoutingPane: Equatable {
    package var id: PaneID
    package var currentDirectory: URL
    package var selectedURLs: [URL]
    package var focusedURL: URL?
    package var focusedItemIsSymbolicLink: Bool
    package var tabCount: Int

    package init(id: PaneID, currentDirectory: URL, selectedURLs: [URL] = [], focusedURL: URL? = nil, focusedItemIsSymbolicLink: Bool = false, tabCount: Int = 1) {
        self.id = id
        self.currentDirectory = currentDirectory
        self.selectedURLs = selectedURLs
        self.focusedURL = focusedURL
        self.focusedItemIsSymbolicLink = focusedItemIsSymbolicLink
        self.tabCount = tabCount
    }
}

package struct MainCommandRoutingState: Equatable {
    package var activePaneID: PaneID
    package var leftPane: MainCommandRoutingPane
    package var rightPane: MainCommandRoutingPane
    package var isSinglePaneMode: Bool
    package var isFileOperationActive: Bool
    package var sandboxAllowsSelectedURLs: Bool
    package var hasUndoRecovery: Bool

    package init(
        activePaneID: PaneID = .left,
        leftPane: MainCommandRoutingPane,
        rightPane: MainCommandRoutingPane,
        isSinglePaneMode: Bool = false,
        isFileOperationActive: Bool = false,
        sandboxAllowsSelectedURLs: Bool = true,
        hasUndoRecovery: Bool = false
    ) {
        self.activePaneID = activePaneID
        self.leftPane = leftPane
        self.rightPane = rightPane
        self.isSinglePaneMode = isSinglePaneMode
        self.isFileOperationActive = isFileOperationActive
        self.sandboxAllowsSelectedURLs = sandboxAllowsSelectedURLs
        self.hasUndoRecovery = hasUndoRecovery
    }

    package var activePane: MainCommandRoutingPane {
        activePaneID == .left ? leftPane : rightPane
    }

    package var inactivePane: MainCommandRoutingPane {
        activePaneID == .left ? rightPane : leftPane
    }
}

package enum MainCommandRoutingDisabledReason: Equatable {
    case noSelection
    case noFocusedItem
    case noRealFocusedItem
    case noOppositePane
    case sandboxRejectedSelection
    case fileOperationInProgress
    case noActiveFileOperation
    case noUndoRecovery
    case focusedItemIsNotSymbolicLink
    case lastTab
}

package enum MainCommandRoute: Equatable {
    case activePane(command: MainCommand, pane: PaneID, urls: [URL])
    case crossPane(command: MainCommand, sourcePane: PaneID, destinationPane: PaneID, sourceURLs: [URL], destinationDirectory: URL)
    case switchPane(to: PaneID)
    case dualPane(command: MainCommand, activePane: PaneID, oppositePane: PaneID)
    case focusedItem(command: MainCommand, pane: PaneID, url: URL)
    case symbolicLink(command: MainCommand, pane: PaneID, url: URL)
    case enabled(command: MainCommand)
    case disabled(command: MainCommand, reason: MainCommandRoutingDisabledReason)
}

package struct MainCommandRouter {
    package init() {}

    /// Entry surfaces intentionally share this path so none can acquire its own
    /// availability or target-selection rules.
    package func route(_ command: MainCommand, from _: MainCommandEntrySurface, in state: MainCommandRoutingState) -> MainCommandRoute {
        route(command, in: state)
    }

    package func route(_ command: MainCommand, in state: MainCommandRoutingState) -> MainCommandRoute {
        if state.isFileOperationActive, command.conflictsWithFileOperation {
            return .disabled(command: command, reason: .fileOperationInProgress)
        }
        if command == .undo { return state.hasUndoRecovery ? .enabled(command: command) : .disabled(command: command, reason: .noUndoRecovery) }
        if command == .cancelOperation {
            return state.isFileOperationActive ? .enabled(command: command) : .disabled(command: command, reason: .noActiveFileOperation)
        }

        switch command {
        case .closeTab:
            guard state.activePane.tabCount > 1 else { return .disabled(command: command, reason: .lastTab) }
            return .activePane(command: command, pane: state.activePaneID, urls: [])
        case .switchPane:
            return .switchPane(to: state.activePaneID.opposite)
        case .swapPanes, .syncOppositePane:
            guard !state.isSinglePaneMode else { return .disabled(command: command, reason: .noOppositePane) }
            return .dualPane(command: command, activePane: state.activePaneID, oppositePane: state.inactivePane.id)
        case .revealInOppositePane:
            guard !state.isSinglePaneMode else { return .disabled(command: command, reason: .noOppositePane) }
            return focusedRoute(command, in: state) {
                .focusedItem(command: command, pane: state.activePaneID, url: $0)
            }
        case .selectSameExtension, .deselectSameExtension:
            guard state.activePane.focusedURL != nil else {
                return .disabled(command: command, reason: .noRealFocusedItem)
            }
            return .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
        case .followSymbolicLink:
            guard state.activePane.focusedItemIsSymbolicLink else {
                return .disabled(command: command, reason: .focusedItemIsNotSymbolicLink)
            }
            return focusedRoute(command, in: state) {
                .symbolicLink(command: command, pane: state.activePaneID, url: $0)
            }
        case .copy, .move:
            guard !state.isSinglePaneMode else {
                return .disabled(command: command, reason: .noOppositePane)
            }
            return selectedRoute(command, in: state) {
                .crossPane(
                    command: command,
                    sourcePane: state.activePaneID,
                    destinationPane: state.inactivePane.id,
                    sourceURLs: state.activePane.selectedURLs,
                    destinationDirectory: state.inactivePane.currentDirectory
                )
            }
        case .copyToClipboard, .cutToClipboard:
            return selectedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
            }
        case .open, .viewer, .quickLook, .rename, .extractArchive, .getInfo, .reveal:
            return focusedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: [$0])
            }
        case .openWith, .trash, .duplicate, .batchRename, .createArchive:
            return selectedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
            }
        case .refresh, .toggleHiddenFiles, .sortByName, .sortByExtension, .sortByKind, .sortBySize, .sortByModified, .sortByCreated, .sortByAdded, .sortByAccessed, .sortAscending, .sortDescending, .back, .forward, .parent, .selectAll, .deselectAll, .selectByPattern, .deselectByPattern, .invertSelection, .newTab, .nextTab, .previousTab:
            return .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
        default:
            return .enabled(command: command)
        }
    }

    private func selectedRoute(_ command: MainCommand, in state: MainCommandRoutingState, build: () -> MainCommandRoute) -> MainCommandRoute {
        guard !state.activePane.selectedURLs.isEmpty else {
            return .disabled(command: command, reason: .noSelection)
        }
        guard state.sandboxAllowsSelectedURLs else {
            return .disabled(command: command, reason: .sandboxRejectedSelection)
        }
        return build()
    }

    private func focusedRoute(_ command: MainCommand, in state: MainCommandRoutingState, build: (URL) -> MainCommandRoute) -> MainCommandRoute {
        guard let focusedURL = state.activePane.focusedURL else {
            return .disabled(command: command, reason: .noFocusedItem)
        }
        guard state.sandboxAllowsSelectedURLs else {
            return .disabled(command: command, reason: .sandboxRejectedSelection)
        }
        return build(focusedURL)
    }
}

package enum ScratchDirectoryCommandRoute: Equatable {
    case promptForConfiguration
    case requestAccess(URL)
    case navigate(URL)
    case cancelled
}

/// Keeps scratch-location command decisions independent from AppKit prompts so
/// every non-mutating and recovery outcome can be covered by routing tests.
package struct ScratchDirectoryCommandRouter {
    package init() {}

    package func route(configuredDirectory: URL?, canAccess: (URL) -> Bool) -> ScratchDirectoryCommandRoute {
        guard let configuredDirectory else { return .promptForConfiguration }
        return canAccess(configuredDirectory) ? .navigate(configuredDirectory) : .requestAccess(configuredDirectory)
    }

    package func routeAfterAccessRecovery(to directory: URL, wasGranted: Bool) -> ScratchDirectoryCommandRoute {
        wasGranted ? .navigate(directory) : .cancelled
    }
}

package extension MainCommand {
    var conflictsWithFileOperation: Bool {
        switch self {
        case .newFile, .newFolder, .rename, .batchRename, .createArchive, .extractArchive, .duplicate, .undo, .copy, .move, .trash, .cutToClipboard, .pasteFromClipboard:
            return true
        default:
            return false
        }
    }
}

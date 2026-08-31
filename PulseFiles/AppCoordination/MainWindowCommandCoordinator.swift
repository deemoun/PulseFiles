// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
import PulseFilesWorkflows

/// Application-layer command boundary. It assembles the window's transient
/// validation snapshot, while `MainCommandRouter` remains the value-only
/// decision engine.
@MainActor
package final class MainWindowCommandCoordinator {
    package struct PaneSnapshot {
        package let id: PaneID
        package let currentDirectory: URL
        package let selectedURLs: [URL]
        package let focusedURL: URL?
        package let focusedItemIsSymbolicLink: Bool
        package let tabCount: Int

        package init(id: PaneID, currentDirectory: URL, selectedURLs: [URL], focusedURL: URL?, focusedItemIsSymbolicLink: Bool, tabCount: Int) {
            self.id = id
            self.currentDirectory = currentDirectory
            self.selectedURLs = selectedURLs
            self.focusedURL = focusedURL
            self.focusedItemIsSymbolicLink = focusedItemIsSymbolicLink
            self.tabCount = tabCount
        }

        var routingPane: MainCommandRoutingPane {
            MainCommandRoutingPane(
                id: id,
                currentDirectory: currentDirectory,
                selectedURLs: selectedURLs,
                focusedURL: focusedURL,
                focusedItemIsSymbolicLink: focusedItemIsSymbolicLink,
                tabCount: tabCount
            )
        }
    }

    package struct Inputs {
        package let activePaneID: () -> PaneID
        package let pane: (PaneID) -> PaneSnapshot
        package let isSinglePaneMode: () -> Bool
        package let isFileOperationActive: () -> Bool
        package let hasUndoRecovery: () -> Bool
        package let canAccess: (URL) -> Bool

        package init(activePaneID: @escaping () -> PaneID, pane: @escaping (PaneID) -> PaneSnapshot, isSinglePaneMode: @escaping () -> Bool, isFileOperationActive: @escaping () -> Bool, hasUndoRecovery: @escaping () -> Bool, canAccess: @escaping (URL) -> Bool) {
            self.activePaneID = activePaneID
            self.pane = pane
            self.isSinglePaneMode = isSinglePaneMode
            self.isFileOperationActive = isFileOperationActive
            self.hasUndoRecovery = hasUndoRecovery
            self.canAccess = canAccess
        }
    }

    private let router: MainCommandRouter
    private let inputs: Inputs
    private let output: (MainCommandRoute) -> Void

    package init(router: MainCommandRouter = .init(), inputs: Inputs, output: @escaping (MainCommandRoute) -> Void) {
        self.router = router
        self.inputs = inputs
        self.output = output
    }

    package func state() -> MainCommandRoutingState {
        let activePaneID = inputs.activePaneID()
        let left = inputs.pane(.left)
        let right = inputs.pane(.right)
        let active = activePaneID == .left ? left : right
        let protectedURLs = active.selectedURLs + [active.focusedURL].compactMap { $0 }
        return MainCommandRoutingState(
            activePaneID: activePaneID,
            leftPane: left.routingPane,
            rightPane: right.routingPane,
            isSinglePaneMode: inputs.isSinglePaneMode(),
            isFileOperationActive: inputs.isFileOperationActive(),
            sandboxAllowsSelectedURLs: protectedURLs.allSatisfy(inputs.canAccess),
            hasUndoRecovery: inputs.hasUndoRecovery()
        )
    }

    @discardableResult
    package func perform(_ command: MainCommand, from surface: MainCommandEntrySurface) -> MainCommandRoute {
        let route = router.route(command, from: surface, in: state())
        output(route)
        return route
    }

    package func route(_ command: MainCommand, from surface: MainCommandEntrySurface = .menu) -> MainCommandRoute {
        router.route(command, from: surface, in: state())
    }
}

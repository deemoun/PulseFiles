// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Application-layer command boundary. It assembles the window's transient
/// validation snapshot, while `MainCommandRouter` remains the value-only
/// decision engine.
@MainActor
final class MainWindowCommandCoordinator {
    struct PaneSnapshot {
        let id: PaneID
        let currentDirectory: URL
        let selectedURLs: [URL]
        let focusedURL: URL?
        let focusedItemIsSymbolicLink: Bool
        let tabCount: Int

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

    struct Inputs {
        let activePaneID: () -> PaneID
        let pane: (PaneID) -> PaneSnapshot
        let isSinglePaneMode: () -> Bool
        let isFileOperationActive: () -> Bool
        let hasUndoRecovery: () -> Bool
        let canAccess: (URL) -> Bool
    }

    private let router: MainCommandRouter
    private let inputs: Inputs
    private let output: (MainCommandRoute) -> Void

    init(router: MainCommandRouter = .init(), inputs: Inputs, output: @escaping (MainCommandRoute) -> Void) {
        self.router = router
        self.inputs = inputs
        self.output = output
    }

    func state() -> MainCommandRoutingState {
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
    func perform(_ command: MainCommand, from surface: MainCommandEntrySurface) -> MainCommandRoute {
        let route = router.route(command, from: surface, in: state())
        output(route)
        return route
    }

    func route(_ command: MainCommand, from surface: MainCommandEntrySurface = .menu) -> MainCommandRoute {
        router.route(command, from: surface, in: state())
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// The deliberately small boundary between command routing and feature code.
/// Entry points submit an intent; only `MainCommandRouter` decides whether and
/// where that intent is allowed to execute.
@MainActor
protocol MainCommandHandling: AnyObject {
    func handle(_ route: MainCommandRoute)
}

@MainActor
final class MainCommandDispatchCoordinator {
    private let router: MainCommandRouter
    private weak var handler: (any MainCommandHandling)?

    init(router: MainCommandRouter = .init(), handler: any MainCommandHandling) {
        self.router = router
        self.handler = handler
    }

    @discardableResult
    func dispatch(
        _ command: MainCommand,
        from surface: MainCommandEntrySurface,
        state: MainCommandRoutingState
    ) -> MainCommandRoute {
        let route = router.route(command, from: surface, in: state)
        handler?.handle(route)
        return route
    }
}

/// Narrow seams used by the window workflow coordinators. They intentionally
/// expose no view-controller concrete types and no filesystem mutation API.
@MainActor
protocol MainWindowAlertPresenting: AnyObject {
    func presentAlert(message: String, detail: String, style: NSAlert.Style)
}

@MainActor
protocol MainWindowPaneAccessing: AnyObject {
    func currentDirectory(for pane: PaneID) -> URL
    func selectedURLs(for pane: PaneID) -> [URL]
    func refresh(_ pane: PaneID)
}

@MainActor
protocol FileOperationProgressPresenting: AnyObject {
    func show(operationName: String)
    func update(operationName: String, progress: FileOperationProgress)
    func showCancellationPending()
    func dismiss()
}

@MainActor
protocol MainWindowSettingsUpdating: AnyObject {
    func setSidebarVisible(_ visible: Bool)
    func setTerminalVisible(_ visible: Bool)
    func setSidebarWidth(_ width: Double)
}

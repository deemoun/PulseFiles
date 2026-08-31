// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesWorkflows

/// The deliberately small boundary between command routing and feature code.
/// Entry points submit an intent; only `MainCommandRouter` decides whether and
/// where that intent is allowed to execute.
@MainActor
package protocol MainCommandHandling: AnyObject {
    func handle(_ route: MainCommandRoute)
}

@MainActor
package final class MainCommandDispatchCoordinator {
    private let router: MainCommandRouter
    private weak var handler: (any MainCommandHandling)?

    package init(router: MainCommandRouter = .init(), handler: any MainCommandHandling) {
        self.router = router
        self.handler = handler
    }

    @discardableResult
    package func dispatch(
        _ command: MainCommand,
        from surface: MainCommandEntrySurface,
        state: MainCommandRoutingState
    ) -> MainCommandRoute {
        let route = router.route(command, from: surface, in: state)
        handler?.handle(route)
        return route
    }
}

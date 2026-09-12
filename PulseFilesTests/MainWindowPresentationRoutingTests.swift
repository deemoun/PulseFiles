// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import PulseFilesAppCoordination
import PulseFilesModels

final class MainWindowPresentationRoutingTests: XCTestCase {
    func testPaneArrangementRoutesSingleAndDualPaneState() {
        XCTAssertEqual(PaneArrangementRoute(singlePane: true, focusedPane: .right).visiblePanes, [.right])
        XCTAssertEqual(PaneArrangementRoute(singlePane: false, focusedPane: .right).visiblePanes, [.left, .right])
        XCTAssertTrue(PaneArrangementRoute(singlePane: false, focusedPane: .left).hasOppositePane)
    }

    func testDeletePromptRoutingPreservesPermanentConfirmation() {
        XCTAssertEqual(DeletePromptRoute.resolve(itemCount: 0, permanently: false, confirmsTrash: false), .nothingSelected)
        XCTAssertEqual(DeletePromptRoute.resolve(itemCount: 1, permanently: false, confirmsTrash: false), .performImmediately(permanently: false))
        XCTAssertEqual(DeletePromptRoute.resolve(itemCount: 1, permanently: true, confirmsTrash: false), .confirm(permanently: true))
    }
}

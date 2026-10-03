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

    func testPaneRefreshCoordinatorTargetsRenameSourceAndKeepsOtherPaneGeneric() {
        let source = URL(fileURLWithPath: "/work/source/old.txt")
        let renamed = URL(fileURLWithPath: "/work/source/new.txt")
        let result = FileOperationResult(completedItems: [renamed], skippedItems: [], failedItems: [], wasCancelled: false)

        let route = PaneRefreshCoordinator().afterRename(
            currentDirectories: [source.deletingLastPathComponent(), URL(fileURLWithPath: "/work/other")],
            sourceURL: source,
            result: result
        )

        XCTAssertEqual(route.genericPaneIndexes, [1])
        XCTAssertEqual(route.targetedReload, .init(paneIndexes: [0], selectionURL: renamed))
        XCTAssertTrue(route.restoresFocusedPane)
    }

    func testPaneRefreshCoordinatorUsesGenericRefreshForTransferDeleteAndRecovery() {
        let coordinator = PaneRefreshCoordinator()
        let expected = PaneRefreshRoute(genericPaneIndexes: [0, 1])
        XCTAssertEqual(coordinator.afterTransfer(paneCount: 2), expected)
        XCTAssertEqual(coordinator.afterDelete(paneCount: 2), expected)
        XCTAssertEqual(coordinator.afterRecovery(paneCount: 2), expected)
    }
}

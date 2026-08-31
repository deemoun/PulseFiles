// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesAppCoordination

final class RenamePaneRefreshPlanTests: XCTestCase {
    func testRenameRefreshesOnlyPaneViewingSourceDirectory() {
        let sourceDirectory = URL(fileURLWithPath: "/sandbox/source", isDirectory: true)
        let otherDirectory = URL(fileURLWithPath: "/sandbox/other", isDirectory: true)

        let plan = RenamePaneRefreshPlan(
            currentDirectories: [sourceDirectory, otherDirectory],
            sourceURL: sourceDirectory.appendingPathComponent("Old name.txt")
        )

        XCTAssertEqual(plan.renamedPaneIndexes, [0])
        XCTAssertEqual(plan.genericRefreshPaneIndexes, [1])
    }

    func testRenameRefreshesBothPanesViewingSourceDirectory() {
        let sourceDirectory = URL(fileURLWithPath: "/sandbox/source", isDirectory: true)

        let plan = RenamePaneRefreshPlan(
            currentDirectories: [sourceDirectory, sourceDirectory],
            sourceURL: sourceDirectory.appendingPathComponent("Old name.txt")
        )

        XCTAssertEqual(plan.renamedPaneIndexes, [0, 1])
        XCTAssertTrue(plan.genericRefreshPaneIndexes.isEmpty)
    }

    func testDirectoryMonitorNotificationDuringRenameKeepsTargetedPanesOutOfGenericRefresh() {
        // A monitor notification can cause another reload while the explicit
        // rename reload is in flight. The generic completion path must still
        // exclude the pane that owns the renamed item's selection.
        let sourceDirectory = URL(fileURLWithPath: "/sandbox/source", isDirectory: true)
        let otherDirectory = URL(fileURLWithPath: "/sandbox/other", isDirectory: true)
        let planBeforeMonitorNotification = RenamePaneRefreshPlan(
            currentDirectories: [sourceDirectory, otherDirectory],
            sourceURL: sourceDirectory.appendingPathComponent("Old name.txt")
        )
        let planAfterMonitorNotification = RenamePaneRefreshPlan(
            currentDirectories: [sourceDirectory, otherDirectory],
            sourceURL: sourceDirectory.appendingPathComponent("Old name.txt")
        )

        XCTAssertEqual(planBeforeMonitorNotification.renamedPaneIndexes, [0])
        XCTAssertEqual(planAfterMonitorNotification.renamedPaneIndexes, [0])
        XCTAssertEqual(planAfterMonitorNotification.genericRefreshPaneIndexes, [1])
    }
}

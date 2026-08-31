// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesModels

final class PaneNavigationStateMachineTests: XCTestCase {
    func testHistoryTransitionCanBeCommittedAndRolledBack() throws {
        let first = URL(fileURLWithPath: "/first")
        let second = URL(fileURLWithPath: "/second")
        var history = NavigationHistory(initialURL: first)
        history.visit(second)
        var machine = PaneNavigationStateMachine(state: PaneState(currentDirectory: second, history: history))
        let transition = try XCTUnwrap(machine.backTransition())
        machine.commitDirectory(transition.directory, addToHistory: false, transition: transition)
        XCTAssertEqual(machine.state.currentDirectory, first)
        machine.rollBack(transition)
        XCTAssertEqual(machine.state.history.backStack.last, first)
    }

    func testTabActivationStoresOutgoingSearchAndRestoresIncomingState() {
        let first = PaneTabState(currentDirectory: URL(fileURLWithPath: "/first"))
        var second = PaneTabState(currentDirectory: URL(fileURLWithPath: "/second"))
        second.searchQuery = "incoming"
        var machine = PaneNavigationStateMachine(state: PaneState(tabs: [first, second], activeTabID: first.id))
        XCTAssertTrue(machine.activateTab(id: second.id, savingSearchQuery: "outgoing"))
        XCTAssertEqual(machine.state.tabs[0].searchQuery, "outgoing")
        XCTAssertEqual(machine.state.searchQuery, "incoming")
    }

    func testRestorationStandardizesActiveDirectory() {
        var machine = PaneNavigationStateMachine(state: PaneState(currentDirectory: URL(fileURLWithPath: "/old")))
        machine.restore(PaneState(currentDirectory: URL(fileURLWithPath: "/new/../new")))
        XCTAssertEqual(machine.state.currentDirectory, URL(fileURLWithPath: "/new"))
    }
}

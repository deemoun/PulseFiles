// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
import PulseFilesPresentationCommands
@testable import PulseFiles

final class DualPaneCommandTests: XCTestCase {
    private let leftURL = URL(fileURLWithPath: "/left")
    private let rightURL = URL(fileURLWithPath: "/right")

    func testDualPaneCommandsUseExplicitRoutes() {
        let router = MainCommandRouter()
        let state = routingState(focusedURL: leftURL.appendingPathComponent("item"), isSymbolicLink: true)

        XCTAssertEqual(router.route(.swapPanes, in: state), .dualPane(command: .swapPanes, activePane: .left, oppositePane: .right))
        XCTAssertEqual(router.route(.syncOppositePane, in: state), .dualPane(command: .syncOppositePane, activePane: .left, oppositePane: .right))
        XCTAssertEqual(router.route(.revealInOppositePane, in: state), .focusedItem(command: .revealInOppositePane, pane: .left, url: leftURL.appendingPathComponent("item")))
        XCTAssertEqual(router.route(.followSymbolicLink, in: state), .symbolicLink(command: .followSymbolicLink, pane: .left, url: leftURL.appendingPathComponent("item")))
    }

    func testOppositePaneCommandsAreDisabledInSinglePaneMode() {
        var state = routingState(focusedURL: leftURL.appendingPathComponent("item"), isSymbolicLink: true)
        state.isSinglePaneMode = true
        for command in [MainCommand.swapPanes, .syncOppositePane, .revealInOppositePane] {
            XCTAssertEqual(MainCommandRouter().route(command, in: state), .disabled(command: command, reason: .noOppositePane))
        }
    }

    func testFollowRequiresFocusedSymbolicLink() {
        let state = routingState(focusedURL: leftURL.appendingPathComponent("file"), isSymbolicLink: false)
        XCTAssertEqual(MainCommandRouter().route(.followSymbolicLink, in: state), .disabled(command: .followSymbolicLink, reason: .focusedItemIsNotSymbolicLink))
    }

    func testNewShortcutsAreUnavailableDuringTextInput() {
        let router = MainCommandRouter()
        XCTAssertEqual(router.commandForKeyDown(keyCode: 32, command: true), .swapPanes)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 32, command: true, option: true), .syncOppositePane)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 36, option: true), .revealInOppositePane)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 124, command: true), .followSymbolicLink)
        XCTAssertNil(router.commandForKeyDown(keyCode: 32, command: true, isTextInputFocused: true))
    }

    private func routingState(focusedURL: URL?, isSymbolicLink: Bool) -> MainCommandRoutingState {
        MainCommandRoutingState(
            leftPane: MainCommandRoutingPane(id: .left, currentDirectory: leftURL, focusedURL: focusedURL, focusedItemIsSymbolicLink: isSymbolicLink),
            rightPane: MainCommandRoutingPane(id: .right, currentDirectory: rightURL)
        )
    }
}

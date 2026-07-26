import XCTest
import AppKit
@testable import PulseFiles

final class DualPaneCommandTests: XCTestCase {
    private func state(single: Bool = false, focused: URL? = nil, isLink: Bool = false) -> MainCommandRoutingState {
        MainCommandRoutingState(
            leftPane: MainCommandRoutingPane(id: .left, currentDirectory: URL(fileURLWithPath: "/left"), focusedURL: focused),
            rightPane: MainCommandRoutingPane(id: .right, currentDirectory: URL(fileURLWithPath: "/right")),
            isSinglePaneMode: single,
            focusedItemIsSymbolicLink: isLink
        )
    }

    func testOppositePaneCommandsRejectSinglePaneMode() {
        for command in [MainCommand.swapPanes, .syncOppositePane, .revealInOppositePane] {
            XCTAssertEqual(MainCommandRouter().route(command, in: state(single: true)), .disabled(command: command, reason: .noOppositePane))
        }
    }

    func testSymbolicLinkEligibilityIsExplicit() {
        let url = URL(fileURLWithPath: "/left/link")
        XCTAssertEqual(MainCommandRouter().route(.followSymbolicLink, in: state(focused: url)), .disabled(command: .followSymbolicLink, reason: .focusedItemIsNotSymbolicLink))
        XCTAssertEqual(MainCommandRouter().route(.followSymbolicLink, in: state(focused: url, isLink: true)), .symbolicLink(command: .followSymbolicLink, pane: .left, url: url))
    }

    func testNewShortcutsNeverRunInTextEditors() {
        let router = MainCommandRouter()
        for (key, command, option) in [(UInt16(32), MainCommand.swapPanes, false), (32, .syncOppositePane, true), (36, .revealInOppositePane, true), (124, .followSymbolicLink, false)] {
            XCTAssertEqual(router.commandForKeyDown(keyCode: key, command: !option || command == .syncOppositePane, option: option), command)
            XCTAssertNil(router.commandForKeyDown(keyCode: key, command: !option || command == .syncOppositePane, option: option, isTextInputFocused: true))
        }
    }
}

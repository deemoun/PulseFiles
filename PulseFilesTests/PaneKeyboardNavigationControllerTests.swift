import XCTest
@testable import PulseFiles

final class PaneKeyboardNavigationControllerTests: XCTestCase {
    private let controller = PaneKeyboardNavigationController()

    func testPlainArrowsMapToPaneNavigationActions() {
        XCTAssertEqual(controller.action(keyCode: 123, modifiers: []), .navigateToParent)
        XCTAssertEqual(controller.action(keyCode: 124, modifiers: []), .openFocusedItem)
        XCTAssertEqual(controller.action(keyCode: 125, modifiers: []), .moveFocus(delta: 1))
        XCTAssertEqual(controller.action(keyCode: 126, modifiers: []), .moveFocus(delta: -1))
    }

    func testModifiedArrowsRemainUnhandledForAppKitAndCommandRouting() {
        let modifiers: [PaneKeyboardModifiers] = [.shift, .command, .option, .control, [.command, .shift]]
        for modifier in modifiers {
            for keyCode: UInt16 in 123...126 {
                XCTAssertEqual(controller.action(keyCode: keyCode, modifiers: modifier), .unhandled)
            }
        }

        XCTAssertEqual(
            MainCommandRouter().commandForKeyDown(keyCode: 124, command: true),
            .followSymbolicLink,
            "Command-Right must remain available to MainCommandRouter"
        )
        XCTAssertNil(
            MainCommandRouter().commandForKeyDown(
                keyCode: 124,
                command: true,
                isTextInputFocused: true
            ),
            "An active text editor must retain its arrow-key cursor gestures"
        )
    }

    func testUnrelatedKeyIsUnhandled() {
        XCTAssertEqual(controller.action(keyCode: 0, modifiers: []), .unhandled)
    }
}

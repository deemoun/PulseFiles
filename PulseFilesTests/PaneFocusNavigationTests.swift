import XCTest
@testable import PulseFiles

final class PaneFocusNavigationTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/pulsefiles-focus-tests", isDirectory: true)

    func testFocusMovesWithoutReplacingMultipleMarks() {
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        let third = directory.appendingPathComponent("third")
        var state = PaneState(currentDirectory: directory, markedURLs: [first, third], focusedURL: first)

        state.setFocus(PaneFocusNavigation.destination(currentURL: state.focusedURL, visibleURLs: [first, second, third], delta: 1))

        XCTAssertEqual(state.focusedURL, second)
        XCTAssertEqual(state.markedURLs, [first, third], "Keyboard focus must not collapse the drag/file-operation marks.")
    }

    func testFocusSurvivesFilteringAndReturnsWhenVisibleAgain() {
        let first = directory.appendingPathComponent("first")
        let focused = directory.appendingPathComponent("focused")
        let state = PaneState(currentDirectory: directory, markedURLs: [first], focusedURL: focused)

        XCTAssertEqual(state.focusedURL, focused, "Filtering must not replace stable focus with a row-derived value.")
        XCTAssertEqual(PaneFocusNavigation.destination(currentURL: state.focusedURL, visibleURLs: [first, focused], delta: 1), focused)
        XCTAssertEqual(state.markedURLs, [first])
    }

    func testMouseOrAccessibilityFocusCanChangeWithoutChangingOperationMarks() {
        let dragged = directory.appendingPathComponent("dragged")
        let renamed = directory.appendingPathComponent("renamed")
        var state = PaneState(currentDirectory: directory, markedURLs: [dragged], focusedURL: dragged)

        state.setFocus(renamed)

        XCTAssertEqual(state.focusedURL, renamed, "Open and inline rename should target focus.")
        XCTAssertEqual(state.markedURLs, [dragged], "Drag/drop and destructive operations should continue to target marks.")
    }

    func testLegacySelectedURLsAliasMapsToMarkedSet() {
        let item = directory.appendingPathComponent("item")
        var state = PaneState(currentDirectory: directory)

        state.selectedURLs = [item]

        XCTAssertEqual(state.markedURLs, [item])
    }
}

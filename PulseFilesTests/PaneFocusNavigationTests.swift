import XCTest
@testable import PulseFiles

final class PaneFocusNavigationTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/pulsefiles-focus-tests", isDirectory: true)

    func testFocusMovesWithoutReplacingMultipleMarks() {
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        let third = directory.appendingPathComponent("third")
        var state = PaneState(currentDirectory: directory, markedURLs: [first, third], focusedURL: first)

        let destination = PaneFocusNavigation.destination(current: .item(first), displayed: [first, second, third].map { .item($0) }, delta: 1)
        if case let .item(url) = destination { state.setFocus(url) }

        XCTAssertEqual(state.focusedURL, second)
        XCTAssertEqual(state.markedURLs, [first, third], "Keyboard focus must not collapse the drag/file-operation marks.")
    }

    func testFocusSurvivesFilteringAndReturnsWhenVisibleAgain() {
        let first = directory.appendingPathComponent("first")
        let focused = directory.appendingPathComponent("focused")
        let state = PaneState(currentDirectory: directory, markedURLs: [first], focusedURL: focused)

        XCTAssertEqual(state.focusedURL, focused, "Filtering must not replace stable focus with a row-derived value.")
        XCTAssertEqual(PaneFocusNavigation.destination(current: .item(focused), displayed: [first, focused].map { .item($0) }, delta: 1), .item(focused))
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

    func testDisplayedDestinationBoundariesAndMissingFocus() {
        let first = PaneFocusDestination.item(directory.appendingPathComponent("first"))
        let last = PaneFocusDestination.item(directory.appendingPathComponent("last"))
        let displayed: [PaneFocusDestination] = [.parent, first, last]

        XCTAssertEqual(PaneFocusNavigation.destination(current: nil, displayed: displayed, delta: 1), .parent)
        XCTAssertEqual(PaneFocusNavigation.destination(current: nil, displayed: displayed, delta: -1), last)
        XCTAssertEqual(PaneFocusNavigation.destination(current: .parent, displayed: displayed, delta: -1), .parent)
        XCTAssertEqual(PaneFocusNavigation.destination(current: last, displayed: displayed, delta: 1), last)
    }

    func testParentOnlyAndEntirelyEmptyPanes() {
        XCTAssertEqual(PaneFocusNavigation.destination(current: nil, displayed: [.parent], delta: 1), .parent)
        XCTAssertEqual(PaneFocusNavigation.destination(current: nil, displayed: [.parent], delta: -1), .parent)
        XCTAssertNil(PaneFocusNavigation.destination(current: nil, displayed: [], delta: 1))
        XCTAssertNil(PaneFocusNavigation.destination(current: nil, displayed: [], delta: -1))
    }

    func testEveryBoundaryClampsWithoutSkippingAVisibleDestination() {
        let first = PaneFocusDestination.item(directory.appendingPathComponent("first"))
        let second = PaneFocusDestination.item(directory.appendingPathComponent("second"))
        let displayed: [PaneFocusDestination] = [.parent, first, second]

        XCTAssertEqual(PaneFocusNavigation.destination(current: .parent, displayed: displayed, delta: 1), first)
        XCTAssertEqual(PaneFocusNavigation.destination(current: first, displayed: displayed, delta: 1), second)
        XCTAssertEqual(PaneFocusNavigation.destination(current: second, displayed: displayed, delta: -1), first)
        XCTAssertEqual(PaneFocusNavigation.destination(current: first, displayed: displayed, delta: -1), .parent)
        XCTAssertEqual(PaneFocusNavigation.destination(current: .parent, displayed: displayed, delta: -1), .parent)
        XCTAssertEqual(PaneFocusNavigation.destination(current: second, displayed: displayed, delta: 1), second)
    }

    func testLegacySelectedURLsAliasMapsToMarkedSet() {
        let item = directory.appendingPathComponent("item")
        var state = PaneState(currentDirectory: directory)

        state.selectedURLs = [item]

        XCTAssertEqual(state.markedURLs, [item])
    }
}

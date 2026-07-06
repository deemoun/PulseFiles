import XCTest
@testable import PulseFiles

final class MainCommandRoutingTests: XCTestCase {
    private let router = MainCommandRouter()

    func testActivePaneOnlyCommandsRouteToActivePaneSelection() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected])

        XCTAssertEqual(router.route(.open, in: state), .activePane(command: .open, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.rename, in: state), .activePane(command: .rename, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.trash, in: state), .activePane(command: .trash, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.reveal, in: state), .activePane(command: .reveal, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.refresh, in: state), .activePane(command: .refresh, pane: .left, urls: [selected]))
    }

    func testCopyAndMoveRouteSelectionToOppositePaneDirectory() {
        let selected = URL(fileURLWithPath: "/sandbox/right/report.pdf")
        let state = makeState(activePaneID: .right, rightSelection: [selected])
        let leftDirectory = URL(fileURLWithPath: "/sandbox/left", isDirectory: true)

        XCTAssertEqual(
            router.route(.copy, in: state),
            .crossPane(command: .copy, sourcePane: .right, destinationPane: .left, sourceURLs: [selected], destinationDirectory: leftDirectory)
        )
        XCTAssertEqual(
            router.route(.move, in: state),
            .crossPane(command: .move, sourcePane: .right, destinationPane: .left, sourceURLs: [selected], destinationDirectory: leftDirectory)
        )
    }

    func testTabSwitchingAlternatesBetweenLeftAndRightPanes() {
        XCTAssertEqual(router.route(.switchPane, in: makeState(activePaneID: .left)), .switchPane(to: .right))
        XCTAssertEqual(router.route(.switchPane, in: makeState(activePaneID: .right)), .switchPane(to: .left))
        XCTAssertEqual(router.commandForKeyDown(keyCode: 48), .switchPane)
        XCTAssertNil(router.commandForKeyDown(keyCode: 48, command: true), "Command-Tab belongs to the system app switcher.")
    }

    func testSelectionCommandsAreDisabledWhenNoSelectionExists() {
        let state = makeState(activePaneID: .left)

        for command in [MainCommand.open, .rename, .trash, .reveal, .copy, .move, .copyToClipboard, .cutToClipboard] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .noSelection))
        }
        XCTAssertEqual(router.route(.quickLook, in: state), .disabled(command: .quickLook, reason: .noFocusedItem))
    }

    func testSelectionCommandsAreDisabledWhenSandboxRejectsSelectedURL() {
        let selected = URL(fileURLWithPath: "/outside-sandbox/secret.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected], sandboxAllowsSelectedURLs: false)

        for command in [MainCommand.open, .rename, .trash, .reveal, .copy, .move, .copyToClipboard, .cutToClipboard] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .sandboxRejectedSelection))
        }
    }

    func testSearchFieldFocusDoesNotStealStandardTextShortcuts() {
        XCTAssertNil(router.commandForKeyDown(keyCode: 0, command: true, isTextInputFocused: true), "Command-A should remain select-all in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 8, command: true, isTextInputFocused: true), "Command-C should remain copy text in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 7, command: true, isTextInputFocused: true), "Command-X should remain cut text in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 9, command: true, isTextInputFocused: true), "Command-V should remain paste in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 120, isTextInputFocused: true), "F2 should not rename while editing search text.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 49, isTextInputFocused: true), "Space should remain text input in search text fields.")
        XCTAssertEqual(router.commandForKeyDown(keyCode: 50, command: true, isTextInputFocused: true), .toggleTerminal)
    }


    func testSpaceRoutesToQuickLookFocusedItemOutsideTextInput() {
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.png")
        let state = makeState(activePaneID: .left, leftFocusedURL: focused)

        XCTAssertEqual(router.commandForKeyDown(keyCode: 49), .quickLook)
        XCTAssertEqual(router.route(.quickLook, in: state), .activePane(command: .quickLook, pane: .left, urls: [focused]))
    }

    func testQuickLookUsesFocusedItemRatherThanSelection() {
        let selected = URL(fileURLWithPath: "/sandbox/left/selected.txt")
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.png")
        let state = makeState(activePaneID: .left, leftSelection: [selected], leftFocusedURL: focused)

        XCTAssertEqual(router.route(.quickLook, in: state), .activePane(command: .quickLook, pane: .left, urls: [focused]))
    }

    func testClipboardShortcutsRouteWhenTextInputIsNotFocused() {
        XCTAssertEqual(router.commandForKeyDown(keyCode: 8, command: true), .copyToClipboard)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 7, command: true), .cutToClipboard)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 9, command: true), .pasteFromClipboard)
    }

    func testClipboardSelectionCommandsRouteToActivePane() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected])

        XCTAssertEqual(router.route(.copyToClipboard, in: state), .activePane(command: .copyToClipboard, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.cutToClipboard, in: state), .activePane(command: .cutToClipboard, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.pasteFromClipboard, in: state), .enabled(command: .pasteFromClipboard))
    }

    func testFileMutatingCommandsAreDisabledDuringActiveFileOperation() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected], isFileOperationActive: true)

        XCTAssertEqual(router.route(.rename, in: state), .disabled(command: .rename, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.copy, in: state), .disabled(command: .copy, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.move, in: state), .disabled(command: .move, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.cutToClipboard, in: state), .disabled(command: .cutToClipboard, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.pasteFromClipboard, in: state), .disabled(command: .pasteFromClipboard, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.trash, in: state), .disabled(command: .trash, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.refresh, in: state), .activePane(command: .refresh, pane: .left, urls: [selected]))
    }

    private func makeState(
        activePaneID: PaneID,
        leftSelection: [URL] = [],
        rightSelection: [URL] = [],
        leftFocusedURL: URL? = nil,
        rightFocusedURL: URL? = nil,
        isFileOperationActive: Bool = false,
        sandboxAllowsSelectedURLs: Bool = true
    ) -> MainCommandRoutingState {
        MainCommandRoutingState(
            activePaneID: activePaneID,
            leftPane: MainCommandRoutingPane(
                id: .left,
                currentDirectory: URL(fileURLWithPath: "/sandbox/left", isDirectory: true),
                selectedURLs: leftSelection,
                focusedURL: leftFocusedURL ?? leftSelection.first
            ),
            rightPane: MainCommandRoutingPane(
                id: .right,
                currentDirectory: URL(fileURLWithPath: "/sandbox/right", isDirectory: true),
                selectedURLs: rightSelection,
                focusedURL: rightFocusedURL ?? rightSelection.first
            ),
            isFileOperationActive: isFileOperationActive,
            sandboxAllowsSelectedURLs: sandboxAllowsSelectedURLs
        )
    }
}

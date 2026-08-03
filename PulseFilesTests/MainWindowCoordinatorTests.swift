import XCTest
@testable import PulseFiles

final class MainWindowCoordinatorTests: XCTestCase {
    func testPaneCommandCoordinatorReturnsTypedCrossPaneTarget() {
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/left"), selectedURLs: [URL(fileURLWithPath: "/left/a")]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/right"))
        )

        XCTAssertEqual(
            PaneCommandCoordinator().route(.copy, state: state),
            .crossPane(command: .copy, sourcePane: .left, destinationPane: .right, sourceURLs: [URL(fileURLWithPath: "/left/a")], destinationDirectory: URL(fileURLWithPath: "/right"))
        )
    }

    func testPaneCommandCoordinatorRejectsCrossPaneCommandInSinglePaneMode() {
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/left"), selectedURLs: [URL(fileURLWithPath: "/left/a")]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/right")),
            isSinglePaneMode: true
        )

        XCTAssertEqual(
            PaneCommandCoordinator().route(.move, state: state),
            .disabled(command: .move, reason: .noOppositePane)
        )
    }

    @MainActor
    func testFileOperationCoordinatorCapturesOnlyCompleteUndoRecovery() {
        let coordinator = FileOperationCoordinator()
        let recovery = FileOperationRecovery(
            kind: .copy,
            items: [.init(originalURL: URL(fileURLWithPath: "/a"), destinationURL: URL(fileURLWithPath: "/b"))]
        )
        let partial = FileOperationResult(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: true, recovery: recovery)
        coordinator.captureRecovery(from: partial)
        XCTAssertNil(coordinator.undoRecovery)
    }

    func testWindowLayoutControllerTracksIndependentPanelsAndPaneMode() {
        var layout = WindowLayoutController(isSidebarVisible: true, isTerminalVisible: false)
        layout.setSidebarVisible(false)
        layout.setTerminalVisible(true)
        layout.setSinglePane(true)
        XCTAssertFalse(layout.isSidebarVisible)
        XCTAssertTrue(layout.isTerminalVisible)
        XCTAssertTrue(layout.isSinglePane)
    }
}

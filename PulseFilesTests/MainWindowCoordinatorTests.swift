import XCTest
@testable import PulseFiles

final class MainWindowCoordinatorTests: XCTestCase {
    func testMainCommandRouterReturnsTypedCrossPaneTarget() {
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/left"), selectedURLs: [URL(fileURLWithPath: "/left/a")]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/right"))
        )

        XCTAssertEqual(
            MainCommandRouter().route(.copy, in: state),
            .crossPane(command: .copy, sourcePane: .left, destinationPane: .right, sourceURLs: [URL(fileURLWithPath: "/left/a")], destinationDirectory: URL(fileURLWithPath: "/right"))
        )
    }

    func testMainCommandRouterRejectsCrossPaneCommandInSinglePaneMode() {
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/left"), selectedURLs: [URL(fileURLWithPath: "/left/a")]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/right")),
            isSinglePaneMode: true
        )

        XCTAssertEqual(
            MainCommandRouter().route(.move, in: state),
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

    func testTransferWorkflowRejectsDestinationInsideSource() {
        let source = URL(fileURLWithPath: "/tmp/source", isDirectory: true)
        XCTAssertThrowsError(try FileTransferWorkflowCoordinator.validatedRequest(
            sources: [source], destination: source.appendingPathComponent("child", isDirectory: true)
        ))
    }

    func testTransferWorkflowBuildsTypedRequest() throws {
        let sources = [URL(fileURLWithPath: "/tmp/source/file")]
        let destination = URL(fileURLWithPath: "/tmp/destination", isDirectory: true)
        let request = try FileTransferWorkflowCoordinator.validatedRequest(sources: sources, destination: destination)
        XCTAssertEqual(request.sources, sources)
        XCTAssertEqual(request.destinationDirectory, destination)
    }
}

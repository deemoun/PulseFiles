// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class MainWindowCoordinatorTests: XCTestCase {
    @MainActor
    func testCommandDispatchCoordinatorSendsEveryEntrySurfaceThroughOneTypedHandler() {
        let handler = RecordingMainCommandHandler()
        let coordinator = MainCommandDispatchCoordinator(handler: handler)
        let selected = URL(fileURLWithPath: "/sandbox/left/report.txt")
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/sandbox/left"), selectedURLs: [selected]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/sandbox/right"))
        )

        for surface in MainCommandEntrySurface.allCases {
            coordinator.dispatch(.copy, from: surface, state: state)
        }

        XCTAssertEqual(handler.routes.count, MainCommandEntrySurface.allCases.count)
        XCTAssertTrue(handler.routes.allSatisfy { $0 == handler.routes.first })
    }

    @MainActor
    func testCommandDispatchCoordinatorPreservesRouterSafetyRejection() {
        let handler = RecordingMainCommandHandler()
        let coordinator = MainCommandDispatchCoordinator(handler: handler)
        let outside = URL(fileURLWithPath: "/outside/secret")
        let state = MainCommandRoutingState(
            leftPane: .init(id: .left, currentDirectory: URL(fileURLWithPath: "/sandbox/left"), selectedURLs: [outside]),
            rightPane: .init(id: .right, currentDirectory: URL(fileURLWithPath: "/sandbox/right")),
            sandboxAllowsSelectedURLs: false
        )

        for surface in MainCommandEntrySurface.allCases {
            coordinator.dispatch(.move, from: surface, state: state)
        }

        XCTAssertEqual(
            handler.routes,
            Array(repeating: .disabled(command: .move, reason: .sandboxRejectedSelection), count: MainCommandEntrySurface.allCases.count)
        )
    }

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

    func testCommandPresentationDistinguishesParentRowFromMissingSelection() {
        let coordinator = CommandPresentationCoordinator()
        XCTAssertEqual(coordinator.feedback(for: .noSelection, parentRowFocused: false).message, "Nothing Selected")
        XCTAssertEqual(coordinator.feedback(for: .noSelection, parentRowFocused: true).message, "Parent Folder Focused")
        XCTAssertEqual(coordinator.feedback(for: .noUndoRecovery, parentRowFocused: false).detail, "The last operation cannot be safely undone.")
    }

    @MainActor
    func testPaneSynchronizationBuildsRevealIntentAndRejectsStaleVolumeProbe() {
        let coordinator = PaneNavigationSynchronizationCoordinator()
        let item = URL(fileURLWithPath: "/left/folder/report.txt")
        XCTAssertEqual(coordinator.revealPlan(for: item), .init(directory: item.deletingLastPathComponent(), item: item))

        let directories = [URL(fileURLWithPath: "/left"), URL(fileURLWithPath: "/right")]
        let stale = coordinator.beginVolumeProbe()
        let current = coordinator.beginVolumeProbe()
        XCTAssertFalse(coordinator.acceptsVolumeProbe(stale, originalDirectories: directories, currentDirectories: directories))
        XCTAssertTrue(coordinator.acceptsVolumeProbe(current, originalDirectories: directories, currentDirectories: directories))
        XCTAssertFalse(coordinator.acceptsVolumeProbe(current, originalDirectories: directories, currentDirectories: Array(directories.reversed())))
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

    @MainActor
    func testFileOperationCoordinatorOwnsGenerationAndDetachState() {
        let coordinator = FileOperationCoordinator()
        let first = coordinator.begin()
        XCTAssertEqual(first, 1)
        XCTAssertTrue(coordinator.isActive)
        XCTAssertNil(coordinator.begin())
        XCTAssertEqual(coordinator.detach(), first)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(coordinator.acceptsUpdates(for: first!))
        XCTAssertEqual(coordinator.begin(), 3)
    }

    @MainActor
    func testTerminalPresentationCoordinatorRejectsDisabledFirstUseAndTracksVisibility() {
        let coordinator = TerminalPresentationCoordinator(service: TerminalService())
        XCTAssertEqual(coordinator.toggle(isEnabled: false), .disabled)
        XCTAssertFalse(coordinator.isVisible)
        XCTAssertEqual(coordinator.toggle(isEnabled: true), .show)
        XCTAssertTrue(coordinator.isVisible)
        XCTAssertEqual(coordinator.toggle(isEnabled: true), .hide)
        XCTAssertFalse(coordinator.isVisible)
    }

    @MainActor
    func testSidebarLayoutCoordinatorOwnsPersistedWidthClamping() {
        let coordinator = SidebarLayoutCoordinator(minimumWidth: 220, maximumWidth: 340, contentMinimumWidth: 620)
        XCTAssertEqual(coordinator.clampedWidth(100), 220)
        XCTAssertEqual(coordinator.clampedWidth(280), 280)
        XCTAssertEqual(coordinator.clampedWidth(500), 340)
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

    @MainActor
    func testMainWindowCommandCoordinatorAssemblesValidationStateAndEmitsTypedRoute() {
        let selected = URL(fileURLWithPath: "/sandbox/left/report.txt")
        var emitted: MainCommandRoute?
        let coordinator = MainWindowCommandCoordinator(
            inputs: .init(
                activePaneID: { .left },
                pane: { paneID in
                    .init(
                        id: paneID,
                        currentDirectory: URL(fileURLWithPath: "/sandbox/\(paneID == .left ? "left" : "right")", isDirectory: true),
                        selectedURLs: paneID == .left ? [selected] : [], focusedURL: paneID == .left ? selected : nil,
                        focusedItemIsSymbolicLink: false, tabCount: 1
                    )
                },
                isSinglePaneMode: { false }, isFileOperationActive: { false },
                hasUndoRecovery: { false }, canAccess: { $0.path.hasPrefix("/sandbox/") }
            ),
            output: { emitted = $0 }
        )

        let route = coordinator.perform(.copy, from: .menu)
        XCTAssertEqual(route, .crossPane(
            command: .copy, sourcePane: .left, destinationPane: .right,
            sourceURLs: [selected], destinationDirectory: URL(fileURLWithPath: "/sandbox/right", isDirectory: true)
        ))
        XCTAssertEqual(emitted, route)
        XCTAssertTrue(coordinator.state().sandboxAllowsSelectedURLs)
    }

    @MainActor
    func testFileOperationPresentationCoordinatorBuildsConflictAndPartialResultModels() {
        let coordinator = FileOperationPresentationCoordinator()
        let destination = URL(fileURLWithPath: "/tmp/report.txt")
        let conflict = coordinator.conflict(destination: destination, operationName: "Copy", fileExists: { $0 == destination })
        XCTAssertEqual(conflict.0.buttons.count, 4)
        XCTAssertEqual(conflict.1.lastPathComponent, "report 2.txt")

        let result = FileOperationResult(completedItems: [], skippedItems: [destination], failedItems: [], wasCancelled: false)
        XCTAssertNotNil(coordinator.result(result, operationName: "Copy"))
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

    @MainActor
    func testWindowOperationCoordinatorRoutesConflictAndPartialResultThroughPresenterAndRefresh() async throws {
        let root = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("right", isDirectory: true)
        let presenter = RecordingFileOperationPresenter()
        var refreshCount = 0
        let finished = expectation(description: "result presented")
        presenter.onResult = { finished.fulfill() }
        let coordinator = MainWindowFileOperationCoordinator(
            fileOperations: CoordinatorOperationSpy(), state: FileOperationCoordinator(),
            accessPolicy: SandboxFileAccessPolicy(isEnabled: true, rootURL: root), presenter: presenter,
            onActivityChanged: {}, onDefaultRefresh: { refreshCount += 1 }, onResult: { _, _ in }, onOperationStarted: {}
        )

        try coordinator.transfer(named: "Copy", sources: [source], destinationDirectory: destination, shouldConfirm: true) { request, conflict, _ in
            XCTAssertEqual(request.sources, [source])
            _ = await conflict(destination.appendingPathComponent("source.txt"))
            return FileOperationResult(completedItems: [], skippedItems: [source], failedItems: [], wasCancelled: false)
        }

        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(presenter.confirmationCount, 1)
        XCTAssertEqual(presenter.conflictDestinations.count, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(presenter.results.first?.skippedItems, [source])
    }

    @MainActor
    func testWindowOperationCoordinatorRejectsTransferOutsideSharedPolicy() {
        let root = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let presenter = RecordingFileOperationPresenter()
        let coordinator = MainWindowFileOperationCoordinator(
            fileOperations: CoordinatorOperationSpy(), state: FileOperationCoordinator(),
            accessPolicy: SandboxFileAccessPolicy(isEnabled: true, rootURL: root), presenter: presenter,
            onActivityChanged: {}, onDefaultRefresh: {}, onResult: { _, _ in }, onOperationStarted: {}
        )
        XCTAssertThrowsError(try coordinator.transfer(
            named: "Move", sources: [URL(fileURLWithPath: "/outside/file")], destinationDirectory: root,
            shouldConfirm: false, operation: { _, _, _ in .init(completedItems: [], skippedItems: [], failedItems: [], wasCancelled: false) }
        ))
        XCTAssertEqual(presenter.confirmationCount, 0)
    }

    func testArchiveRenameCoordinatorPreservesExtensionsInNumberedNames() {
        let sources = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/folder")]
        XCTAssertEqual(
            ArchiveAndRenameWorkflowCoordinator.proposedNames(for: sources, baseName: "Report"),
            ["Report 1.txt", "Report 2"]
        )
    }

    func testGoToFolderCoordinatorRejectsEmptyPathBeforeProbing() async {
        do {
            _ = try await GoToFolderWorkflowCoordinator.resolvePath(
                "   ", relativeTo: URL(fileURLWithPath: "/tmp"), probe: NeverCalledFileSystemProbe(),
                accessPolicy: SandboxFileAccessPolicy(rootURL: URL(fileURLWithPath: "/tmp"))
            )
            XCTFail("Expected an empty-name validation error")
        } catch { XCTAssertTrue(error is FileNameValidator.ValidationError) }
    }
}

@MainActor
private final class RecordingFileOperationPresenter: FileOperationPresenting {
    var confirmationCount = 0
    var conflictDestinations: [URL] = []
    var results: [FileOperationResult] = []
    var onResult: (() -> Void)?
    func presentFileOperationConfirmation(operationName: String, urls: [URL], destinationDirectory: URL?, confirmButtonTitle: String, completion: @escaping () -> Void) { confirmationCount += 1; completion() }
    func resolveFileOperationConflict(destination: URL, operationName: String) async -> FileConflictResolution { conflictDestinations.append(destination); return .skip }
    func beginFileOperationProgress(named operationName: String) {}
    func updateFileOperationProgress(_ progress: FileOperationProgress, operationName: String) {}
    func endFileOperationProgress() {}
    func showFileOperationCancellationPending() {}
    func presentFileOperationResult(_ result: FileOperationResult, operationName: String) { results.append(result); onResult?() }
    func presentFileOperationError(operationName: String, detail: String) {}
    func presentUndoUnavailable() {}
    func presentDetachedFileOperationWarning() {}
}

private final class CoordinatorOperationSpy: FileOperationCoordinating, @unchecked Sendable {
    func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight { .notRequired }
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func createFolder(named rawName: String, in directory: URL) async throws -> FileOperationResult { fatalError() }
    func createFile(named rawName: String, in directory: URL) async throws -> FileOperationResult { fatalError() }
    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func createArchive(_ request: ArchiveCreateRequest, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func extractArchive(_ request: ArchiveExtractRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func planBatchRename(_ request: BatchRenameRequest) throws -> BatchRenamePlan { fatalError() }
    func batchRename(_ plan: BatchRenamePlan, progressHandler: FileOperationProgressHandler?) async -> FileOperationResult { fatalError() }
}

@MainActor
private final class RecordingMainCommandHandler: MainCommandHandling {
    var routes: [MainCommandRoute] = []
    func handle(_ route: MainCommandRoute) { routes.append(route) }
}

private struct NeverCalledFileSystemProbe: FileSystemProbing {
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { XCTFail("Unexpected probe"); return .value(false) }
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { XCTFail("Unexpected probe"); return .value(false) }
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?> { XCTFail("Unexpected probe"); return .unavailable }
}

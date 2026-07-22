import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class OpenEventRoutingUITests: XCTestCase {
    func testOpenEventRoutesOnlyFirstAccessibleFolderToTheVisibleActivePane() throws {
        let sandboxRoot = ExperimentalFlags.appSandboxRoot
        let fixture = sandboxRoot.appendingPathComponent("OpenEventRoutingUITests-\(UUID().uuidString)", isDirectory: true)
        let firstFolder = fixture.appendingPathComponent("First", isDirectory: true)
        let secondFolder = fixture.appendingPathComponent("Second", isDirectory: true)
        let file = fixture.appendingPathComponent("Ignored.txt")
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxRoot)
        var windowController: MainWindowController?
        let delegate = AppDelegate(accessPolicy: policy) {
            let controller = MainWindowController()
            windowController = controller
            return controller
        }
        defer { windowController?.close() }

        delegate.application(NSApplication.shared, open: [file, secondFolder, firstFolder])

        guard let controller = windowController?.contentViewController as? MainWindowViewController else {
            return XCTFail("Open events must create the production main window controller")
        }
        XCTAssertTrue(windowController?.window?.isVisible == true)
        XCTAssertEqual(controller.uiHarnessState.activePaneID, .left)
        XCTAssertEqual(controller.uiHarnessState.leftDirectory, secondFolder)
        XCTAssertNotEqual(controller.uiHarnessState.rightDirectory, firstFolder)
    }

    func testDeniedFolderOpenLeavesVisiblePaneInItsCurrentDirectoryAndReopenRestoresWindow() throws {
        let sandboxRoot = ExperimentalFlags.appSandboxRoot
        let fixture = sandboxRoot.appendingPathComponent("OpenEventRecoveryUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let deniedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseFilesDeniedOpenEvent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: deniedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: deniedFolder) }

        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxRoot)
        var windowController: MainWindowController?
        let delegate = AppDelegate(accessPolicy: policy) {
            let controller = MainWindowController()
            windowController = controller
            return controller
        }
        defer { windowController?.close() }

        delegate.application(NSApplication.shared, open: [fixture])
        guard let controller = windowController?.contentViewController as? MainWindowViewController else {
            return XCTFail("Open events must create the production main window controller")
        }
        let directoryBeforeDeniedEvent = controller.uiHarnessState.leftDirectory

        delegate.application(NSApplication.shared, open: [deniedFolder])
        XCTAssertEqual(controller.uiHarnessState.leftDirectory, directoryBeforeDeniedEvent)

        windowController?.window?.orderOut(nil)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertTrue(windowController?.window?.isVisible == true)
        XCTAssertEqual(controller.uiHarnessState.leftDirectory, directoryBeforeDeniedEvent)
    }
}

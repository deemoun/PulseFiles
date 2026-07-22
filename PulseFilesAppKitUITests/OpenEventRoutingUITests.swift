import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class OpenEventRoutingUITests: XCTestCase {
    func testOpenEventRoutesOnlyFirstAccessibleFolderToTheVisibleActivePane() throws {
        let fixture = try OpenEventFixture(testCase: self)
        let firstFolder = try fixture.folder("First")
        let secondFolder = try fixture.folder("Second")
        let file = try fixture.file("Ignored.txt")
        let dependencies = fixture.makeDependencies()
        var windowController: MainWindowController?
        let delegate = AppDelegate(
            userDefaults: fixture.defaults,
            accessPolicy: dependencies.policy
        ) {
            let controller = MainWindowController(
                settings: dependencies.settings,
                accessPolicy: dependencies.policy,
                sandboxRootEnsurer: {}
            )
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
        let fixture = try OpenEventFixture(testCase: self)
        let acceptedFolder = try fixture.folder("Accepted")
        let deniedFolder = try fixture.createDeniedFolder()
        let dependencies = fixture.makeDependencies()
        var windowController: MainWindowController?
        let delegate = AppDelegate(
            userDefaults: fixture.defaults,
            accessPolicy: dependencies.policy
        ) {
            let controller = MainWindowController(
                settings: dependencies.settings,
                accessPolicy: dependencies.policy,
                sandboxRootEnsurer: {}
            )
            windowController = controller
            return controller
        }
        defer { windowController?.close() }

        delegate.application(NSApplication.shared, open: [acceptedFolder])
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

@MainActor
private final class OpenEventFixture {
    let root: URL
    let sandboxRoot: URL
    let defaults: UserDefaults
    private let suiteName: String

    init(testCase: XCTestCase) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseFilesOpenEventRoutingUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sandboxRoot = root.appendingPathComponent("Sandbox", isDirectory: true)
        suiteName = "PulseFilesOpenEventRoutingUITests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.defaults = defaults
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        testCase.addTeardownBlock { [root, suiteName] in
            try? FileManager.default.removeItem(at: root)
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    func folder(_ name: String) throws -> URL {
        let url = sandboxRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ name: String) throws -> URL {
        let url = sandboxRoot.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func createDeniedFolder() throws -> URL {
        let url = root.appendingPathComponent("Denied", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeDependencies() -> (settings: SettingsService, policy: SandboxFileAccessPolicy) {
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxRoot)
        let settings = SettingsService(
            defaults: defaults,
            accessPolicy: policy,
            jsonSettingsURLProvider: { [root] in root.appendingPathComponent("Settings.json") },
            homeDirectoryProvider: { [sandboxRoot] in sandboxRoot },
            documentsDirectoryProvider: { [sandboxRoot] in sandboxRoot },
            applicationSupportDirectoryProvider: { [sandboxRoot] in sandboxRoot }
        )
        return (settings, policy)
    }
}

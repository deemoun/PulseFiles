import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class ControllerWiringUITests: XCTestCase {
    private var app: AppKitUIHarness!

    override func setUp() {
        super.setUp()
        app = AppKitUIHarness()
        app.launch()
    }

    override func tearDown() {
        app.close()
        app = nil
        super.tearDown()
    }

    func testFirstLaunchBuildsTheAccessibleDualPaneSurface() {
        // First-launch coverage: these are the identifiers that an external
        // UI driver uses to wait for the initial window and both panes.
        XCTAssertNotNil(app.window.contentView)
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.left))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.right))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.leftTable))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.rightTable))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.leftBreadcrumb))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Pane.rightBreadcrumb))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.CommandBar.panel))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.CommandBar.list))
    }

    func testSettingsLanguageSelectorExposesBothLanguagesAndPersistsSelection() throws {
        let suite = "SettingsLanguageSelector.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        LocalizationConfiguration.configure(language: .english)
        let controller = SettingsViewController(settings: SettingsService(defaults: defaults))
        controller.loadViewIfNeeded()
        let selector = controller.appLanguageSelectorForTesting

        XCTAssertEqual(selector.itemTitles, ["English", "Russian"])
        selector.selectItem(at: 1)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(SettingsService(defaults: defaults).appLanguage, .russian)
    }

    func testMainWindowUsesStableAutosaveNameAndCentersFirstLaunchFallback() {
        XCTAssertEqual(app.window.frameAutosaveName, MainWindowController.frameAutosaveName)

        let visibleFrame = NSRect(x: 100, y: 50, width: 1_600, height: 1_000)
        let fallback = MainWindowFrameLayout.fallbackFrame(in: visibleFrame)

        XCTAssertEqual(fallback.size, MainWindowFrameLayout.defaultFrame.size)
        XCTAssertEqual(fallback.midX, visibleFrame.midX)
        XCTAssertEqual(fallback.midY, visibleFrame.midY)
    }

    func testMainWindowRecoversAnOffScreenSavedFrameIntoAvailableDisplayArea() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_024, height: 700)
        let recovered = MainWindowFrameLayout.clampedFrame(
            NSRect(x: 4_000, y: -1_200, width: 1_280, height: 820),
            availableFrames: [visibleFrame],
            fallbackVisibleFrame: visibleFrame
        )

        XCTAssertEqual(recovered.size, visibleFrame.size)
        XCTAssertEqual(recovered.origin, visibleFrame.origin)
        XCTAssertTrue(visibleFrame.contains(recovered))
    }

    func testToolbarAndKeyboardCommandSelectorsRemainWiredToTheVisibleController() {
        // Exercise the same selectors dispatched by menu items and keyboard
        // shortcuts. The active indicators are stable AX anchors for a future
        // XCUI driver to assert focus after Tab / Command-1 / Command-2.
        let leftIndicator = app.element(AccessibilityIdentifiers.Pane.leftActiveIndicator)
        let rightIndicator = app.element(AccessibilityIdentifiers.Pane.rightActiveIndicator)
        XCTAssertNotNil(leftIndicator.layer)
        XCTAssertNotNil(rightIndicator.layer)

        app.activate(#selector(MainWindowViewController.menuSwitchPane(_:)))
        app.activate(#selector(MainWindowViewController.menuFocusLeftPane(_:)))
        app.activate(#selector(MainWindowViewController.menuFocusRightPane(_:)))
        app.activate(#selector(MainWindowViewController.menuToggleSidebar(_:)))
        app.activate(#selector(MainWindowViewController.menuToggleSidebar(_:)))

        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Toolbar.searchField))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Toolbar.sidebarToggle))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Toolbar.terminalToggle))
    }

    func testIndependentPaneNavigationAndSearchRouteThroughTheActivePane() throws {
        guard let controller = app.window.contentViewController as? MainWindowViewController else {
            return XCTFail("The production main window must host MainWindowViewController")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseFilesAppKitUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let left = root.appendingPathComponent("Left", isDirectory: true)
        let right = root.appendingPathComponent("Right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        controller.uiHarnessNavigate(.left, to: left)
        controller.uiHarnessNavigate(.right, to: right)
        controller.uiHarnessSetSearchQuery("right-only")

        let state = controller.uiHarnessState
        XCTAssertEqual(state.leftDirectory, left)
        XCTAssertEqual(state.rightDirectory, right)
        XCTAssertEqual(state.activePaneID, .right)
        XCTAssertEqual(state.leftSearchQuery, "")
        XCTAssertEqual(state.rightSearchQuery, "right-only")
    }

    func testDoubleClickActivationPreservesIndependentPaneStateAndOpensClickedFolder() async throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let left = root.appendingPathComponent("Left", isDirectory: true)
        let right = root.appendingPathComponent("Right", isDirectory: true)
        let leftFocus = left.appendingPathComponent("left-focus.txt")
        let rightFocus = right.appendingPathComponent("right-focus.txt")
        let folder = right.appendingPathComponent("right-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: leftFocus.path, contents: Data())
        FileManager.default.createFile(atPath: rightFocus.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }

        controller.uiHarnessNavigate(.left, to: left)
        controller.uiHarnessSetSearchQuery("left-focus")
        controller.uiHarnessNavigate(.right, to: right)
        controller.uiHarnessSetSearchQuery("right")
        try await waitUntil { controller.uiHarnessPane(.left).viewModel.visibleItems.contains { $0.url == leftFocus } }
        try await waitUntil { controller.uiHarnessPane(.right).viewModel.visibleItems.contains { $0.url == rightFocus } }
        controller.uiHarnessPane(.left).preparePendingSelection(leftFocus)
        controller.uiHarnessPane(.right).preparePendingSelection(rightFocus)

        // Switch away so the double click genuinely activates this pane while
        // both panes retain distinct, nonempty queries.
        app.activate(#selector(MainWindowViewController.menuFocusLeftPane(_:)))
        try doubleClick(folder, in: controller.uiHarnessPane(.right))
        try await waitUntil { controller.uiHarnessState.rightDirectory == folder }

        let state = controller.uiHarnessState
        XCTAssertEqual(state.activePaneID, .right)
        XCTAssertEqual(state.leftSearchQuery, "left-focus")
        XCTAssertEqual(state.rightSearchQuery, "right")
        XCTAssertEqual(state.leftFocusedURL, leftFocus)
        XCTAssertEqual(state.rightDirectory, folder)
    }

    func testPlainArrowsMoveFocusAfterPaneSwitchWithoutNavigatingOrChangingMarks() async throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        let pane = controller.uiHarnessPane(.right)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt"] {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        defer { try? FileManager.default.removeItem(at: root) }
        controller.uiHarnessNavigate(.right, to: root)
        try await waitUntil { pane.viewModel.visibleItems.count == 3 }
        let first = try XCTUnwrap(pane.viewModel.visibleItems.first?.url)
        pane.preparePendingSelection(first)
        pane.selectItem(at: first)
        let directory = pane.currentDirectory
        let marks = pane.selectedItems.map(\.url)
        app.activate(#selector(MainWindowViewController.menuFocusLeftPane(_:)))
        app.activate(#selector(MainWindowViewController.menuFocusRightPane(_:)))

        pane.tableView.keyDown(with: try arrowEvent(keyCode: 125))
        XCTAssertNotEqual(pane.viewModel.focusedURL, first)
        XCTAssertEqual(pane.currentDirectory, directory)
        XCTAssertEqual(pane.selectedItems.map(\.url), marks)
        pane.tableView.keyDown(with: try arrowEvent(keyCode: 126))
        XCTAssertEqual(pane.viewModel.focusedURL, first)
        XCTAssertEqual(pane.currentDirectory, directory)
        XCTAssertEqual(pane.selectedItems.map(\.url), marks)
    }

    func testEmptyFolderParentActionHasAccurateTitleAndAccessibilityLabel() async throws {
        guard let controller = app.window.contentViewController as? MainWindowViewController else {
            return XCTFail("The production main window must host MainWindowViewController")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseFilesAppKitUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emptyFolder = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        controller.uiHarnessNavigate(.left, to: emptyFolder)

        let identifier = AccessibilityIdentifiers.Pane.contentOverlayAction(for: .left, index: 0)
        var actionButton: NSButton?
        for _ in 0..<100 where actionButton == nil {
            actionButton = findView(in: app.window.contentView, identifier: identifier) as? NSButton
            if actionButton == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let button = try XCTUnwrap(actionButton, "Expected an empty-state parent navigation action")
        XCTAssertEqual(button.title, "Go back".localized)
        XCTAssertEqual(button.accessibilityLabel(), "Go back to parent folder".localized)
    }

    func testWorkflowAnchorsRemainAvailableForOperationsRecentsAndTerminal() {
        // Copy/move conflicts, destructive confirmations, and drag/drop are
        // controller-owned workflows. Their source/destination tables must be
        // addressable before an automation driver injects fixture files.
        XCTAssertTrue(app.element(AccessibilityIdentifiers.Pane.leftTable) is NSTableView)
        XCTAssertTrue(app.element(AccessibilityIdentifiers.Pane.rightTable) is NSTableView)

        // Sidebar recents uses this panel/list pair; keeping both anchors
        // avoids tests depending on a localized "Recent" section title.
        app.activate(#selector(MainWindowViewController.menuToggleSidebar(_:)))
        app.activate(#selector(MainWindowViewController.menuToggleSidebar(_:)))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Sidebar.panel))
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Sidebar.list))

        // Terminal stays opt-in: its toggle is visible, while the panel is not
        // installed until Settings enables the experiment and its warning is
        // acknowledged. This preserves the safety boundary in UI automation.
        XCTAssertNotNil(app.element(AccessibilityIdentifiers.Toolbar.terminalToggle))
        XCTAssertNil(findView(in: app.window.contentView, identifier: AccessibilityIdentifiers.Terminal.panel))
    }

    private func findView(in view: NSView?, identifier: String) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == identifier { return view }
        return view.subviews.lazy.compactMap { findView(in: $0, identifier: identifier) }.first
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for pane state")
    }

    private func doubleClick(_ url: URL, in pane: FilePaneViewController) throws {
        let index = try XCTUnwrap(pane.viewModel.visibleItems.firstIndex { $0.url == url })
        let row = index + (pane.viewModel.searchQuery.isEmpty ? 1 : 0)
        let point = pane.tableView.convert(NSPoint(x: 20, y: pane.tableView.rect(ofRow: row).midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: app.window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 2, pressure: 1))
        pane.tableView.mouseDown(with: event)
    }

    private func arrowEvent(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: app.window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: keyCode))
    }
}

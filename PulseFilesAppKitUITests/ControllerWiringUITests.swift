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
}

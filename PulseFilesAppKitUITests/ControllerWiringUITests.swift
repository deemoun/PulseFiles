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

    func testPaneTableAdaptersPreserveKeyboardAndAccessibilityWiring() throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        for paneID in [PaneID.left, .right] {
            let pane = controller.uiHarnessPane(paneID)
            pane.loadViewIfNeeded()
            XCTAssertNotNil(pane.tableView.delegate)
            XCTAssertNotNil(pane.tableView.dataSource)
            XCTAssertNotNil(pane.tableView.actionDelegate)
            XCTAssertEqual(pane.tableView.accessibilityIdentifier(), AccessibilityIdentifiers.Pane.table(for: paneID))
        }
    }

    func testPaneHeaderActionsStayInsidePaneWhenNarrowed() throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)

        for paneID in [PaneID.left, .right] {
            let pane = controller.uiHarnessPane(paneID)
            pane.loadViewIfNeeded()
            pane.view.frame.size.width = 260
            pane.view.layoutSubtreeIfNeeded()

            let selectorFrame = pane.presentationSelector.convert(pane.presentationSelector.bounds, to: pane.header)
            let hiddenButtonFrame = pane.hiddenButton.convert(pane.hiddenButton.bounds, to: pane.header)
            XCTAssertGreaterThanOrEqual(selectorFrame.minX, pane.header.bounds.minX)
            XCTAssertLessThanOrEqual(hiddenButtonFrame.maxX, pane.header.bounds.maxX)
            XCTAssertLessThanOrEqual(selectorFrame.maxX, hiddenButtonFrame.minX)
        }
    }

    func testSettingsLanguageSelectorExposesBothLanguagesAndPersistsSelection() throws {
        let suite = "SettingsLanguageSelector.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        LocalizationConfiguration.configure(language: .english)
        let controller = SettingsViewController(settings: SettingsService(defaults: defaults), stagingCleanupService: StagingCleanupService(), scratchCleanupService: ScratchFolderCleanupService(), accessPolicy: .current, accessGrantService: .shared, standardFolderAccess: StandardFolderAccessService())
        controller.loadViewIfNeeded()
        let selector = controller.appLanguageSelectorForTesting

        XCTAssertEqual(selector.itemTitles, ["English", "Russian"])
        selector.selectItem(at: 1)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(SettingsService(defaults: defaults).appLanguage, .russian)
    }

    func testSettingsCategoriesSwitchStableRegisteredPages() throws {
        let controller = SettingsViewController(settings: SettingsService(), stagingCleanupService: StagingCleanupService(), scratchCleanupService: ScratchFolderCleanupService(), accessPolicy: .current, accessGrantService: .shared, standardFolderAccess: StandardFolderAccessService())
        controller.loadViewIfNeeded()
        let categories = controller.categoryControlForTesting

        XCTAssertEqual(categories.segmentCount, SettingsViewController.Category.allCases.count)
        for category in SettingsViewController.Category.allCases {
            categories.selectedSegment = category.rawValue
            categories.sendAction(categories.action, to: categories.target)
            XCTAssertTrue(controller.visiblePageForTesting === controller.pageForTesting(category)?.rootView)
        }
    }

    func testSettingsImportantControlsHaveStableAccessibilityIdentifiers() throws {
        let controller = SettingsViewController(settings: SettingsService(), stagingCleanupService: StagingCleanupService(), scratchCleanupService: ScratchFolderCleanupService(), accessPolicy: .current, accessGrantService: .shared, standardFolderAccess: StandardFolderAccessService())
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.categoryControlForTesting.accessibilityIdentifier(), AccessibilityIdentifiers.Settings.categoryControl)
        XCTAssertEqual(controller.appLanguageSelectorForTesting.accessibilityIdentifier(), AccessibilityIdentifiers.Settings.languageSelector)

        let appearance = try XCTUnwrap(controller.pageForTesting(.appearance)?.rootView)
        XCTAssertNotNil(findView(in: appearance, identifier: AccessibilityIdentifiers.Settings.sidebarWidth))
        XCTAssertNotNil(findView(in: appearance, identifier: AccessibilityIdentifiers.Settings.resetPalette))
        let navigation = try XCTUnwrap(controller.pageForTesting(.navigation)?.rootView)
        XCTAssertNotNil(findView(in: navigation, identifier: AccessibilityIdentifiers.Settings.chooseScratchFolder))
        let access = try XCTUnwrap(controller.pageForTesting(.access)?.rootView)
        XCTAssertNotNil(findView(in: access, identifier: AccessibilityIdentifiers.Settings.grantFolderAccess))
    }

    private func findView(in view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        return view.subviews.lazy.compactMap { findView(in: $0, identifier: identifier) }.first
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

    func testPlainArrowsUseWindowPathAndMovePrimarySelectionInOnlyActivePane() async throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for side in ["left", "right"] {
            let directory = root.appendingPathComponent(side, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in ["a.txt", "b.txt", "c.txt"] {
                FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data())
            }
        }
        defer { try? FileManager.default.removeItem(at: root) }

        for (paneID, selector, name) in [(PaneID.left, #selector(MainWindowViewController.menuFocusLeftPane(_:)), "left"),
                                         (.right, #selector(MainWindowViewController.menuFocusRightPane(_:)), "right")] {
            let pane = controller.uiHarnessPane(paneID)
            let directory = root.appendingPathComponent(name, isDirectory: true)
            controller.uiHarnessNavigate(paneID, to: directory)
            try await waitUntil { pane.viewModel.visibleItems.count == 3 }
            let urls = pane.viewModel.visibleItems.map(\.url)
            pane.preparePendingSelection(urls[0])
            pane.selectItem(at: urls[0])
            let otherFocus = controller.uiHarnessPane(paneID == .left ? .right : .left).viewModel.focusedURL
            app.activate(selector)
            app.window.makeFirstResponder(nil)
            XCTAssertNil(app.window.firstResponder, "Pane arrows must not depend on the table remaining first responder")

            try app.postKey(keyCode: 125)
            XCTAssertEqual(pane.viewModel.focusedURL, urls[1], "Down must advance exactly one row")
            XCTAssertTrue(app.window.firstResponder === pane.tableView, "Vertical navigation must restore the active table as first responder")
            XCTAssertEqual(pane.currentDirectory, directory)
            XCTAssertEqual(pane.selectedItems.map(\.url), [urls[1]])
            XCTAssertTrue(pane.tableView.accessibilityFocused())
            let focusedRow = pane.tableView.rowView(atRow: 2, makeIfNecessary: true)
            XCTAssertTrue(focusedRow?.accessibilityFocused() == true)
            XCTAssertEqual(controller.uiHarnessPane(paneID == .left ? .right : .left).viewModel.focusedURL, otherFocus)

            try app.postKey(keyCode: 126)
            XCTAssertEqual(pane.viewModel.focusedURL, urls[0], "Up must retreat exactly one row")
            XCTAssertEqual(pane.selectedItems.map(\.url), [urls[0]])
        }
    }

    func testHorizontalArrowsNavigateDirectoriesAndSafelyConsumeUnavailableNavigation() async throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("a-folder", isDirectory: true)
        let file = root.appendingPathComponent("b-file.txt")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }

        for (paneID, selector) in [(PaneID.left, #selector(MainWindowViewController.menuFocusLeftPane(_:))),
                                   (.right, #selector(MainWindowViewController.menuFocusRightPane(_:)))] {
            let pane = controller.uiHarnessPane(paneID)
            controller.uiHarnessNavigate(paneID, to: root)
            try await waitUntil { pane.viewModel.visibleItems.count == 2 }
            app.activate(selector)
            pane.preparePendingSelection(child)
            try app.postKey(keyCode: 124)
            try await waitUntil { pane.currentDirectory == child }
            try app.postKey(keyCode: 123)
            try await waitUntil { pane.currentDirectory == root }

            pane.preparePendingSelection(file)
            let marks = pane.selectedItems.map(\.url)
            try app.postKey(keyCode: 124)
            XCTAssertEqual(pane.currentDirectory, root, "Right on a regular file is a consumed no-op")
            XCTAssertEqual(pane.viewModel.focusedURL, file)
            XCTAssertEqual(pane.selectedItems.map(\.url), marks)
        }

        let left = controller.uiHarnessPane(.left)
        controller.uiHarnessNavigate(.left, to: URL(fileURLWithPath: "/", isDirectory: true))
        try await waitUntil { left.currentDirectory.path == "/" }
        app.activate(#selector(MainWindowViewController.menuFocusLeftPane(_:)))
        try app.postKey(keyCode: 123)
        XCTAssertEqual(left.currentDirectory.path, "/", "Left at the filesystem root must be safe")
        try app.postKey(keyCode: 124, modifiers: .command)
        XCTAssertEqual(left.currentDirectory.path, "/", "Command-Right remains command routing, not pane descent")
    }

    func testReturnOnParentRowNavigatesToParentWithoutCommandFeedback() async throws {
        let controller = try XCTUnwrap(app.window.contentViewController as? MainWindowViewController)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pane = controller.uiHarnessPane(.left)
        controller.uiHarnessNavigate(.left, to: child)
        try await waitUntil { pane.currentDirectory == child }
        app.activate(#selector(MainWindowViewController.menuFocusLeftPane(_:)))
        pane.setFocusedDestination(.parent)

        try app.postKey(keyCode: 36)

        try await waitUntil { pane.currentDirectory == root }
        XCTAssertNil(app.window.attachedSheet)
    }

    func testArrowEventsRemainEditingGesturesAndRepeatsMoveOnlyOncePerEvent() async throws {
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
        let urls = pane.viewModel.visibleItems.map(\.url)
        pane.preparePendingSelection(urls[0])
        app.activate(#selector(MainWindowViewController.menuFocusRightPane(_:)))

        let search = try XCTUnwrap(app.element(AccessibilityIdentifiers.Toolbar.searchField) as? NSSearchField)
        search.stringValue = "abc"
        app.window.makeFirstResponder(search)
        try app.postKey(keyCode: 123)
        try app.postKey(keyCode: 124)
        XCTAssertEqual(pane.currentDirectory, root)
        XCTAssertEqual(pane.viewModel.focusedURL, urls[0])

        pane.makeTableFirstResponder()
        XCTAssertTrue(pane.beginInlineRename())
        XCTAssertTrue(app.window.firstResponder is NSTextView)
        try app.postKey(keyCode: 123)
        try app.postKey(keyCode: 124)
        XCTAssertEqual(pane.currentDirectory, root)
        XCTAssertEqual(pane.viewModel.focusedURL, urls[0])
        app.window.makeFirstResponder(pane.tableView)

        try app.postKey(keyCode: 125, isRepeat: true)
        XCTAssertEqual(pane.viewModel.focusedURL, urls[1])
        try app.postKey(keyCode: 125, isRepeat: true)
        XCTAssertEqual(pane.viewModel.focusedURL, urls[2])
        for _ in 0..<20 { try app.postKey(keyCode: 125, isRepeat: true) }
        XCTAssertEqual(pane.viewModel.focusedURL, urls[2], "Rapid repeats clamp at the final row")
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

}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import PulseFiles

/// Shared contract for top-level app page objects.
///
/// The current conformer is a logic-backed unit-test robot. A future
/// `PulseFilesUITests` bundle can provide an `XCUIApplication`-backed page object
/// with the same user-facing vocabulary.
@MainActor
protocol AppPageObject: AnyObject {
    associatedtype Pane: FilePanePageObject

    var activePaneID: PaneID { get }
    var activePane: Pane { get }

    @discardableResult
    func switchPane() -> Self

    @discardableResult
    func setActivePane(_ paneID: PaneID) -> Self
}

/// Shared contract for file-pane page objects.
///
/// Keep this protocol focused on user-observable pane behavior so it can be
/// implemented both by view-model-backed robots and future `XCUIElement`-backed
/// pages.
@MainActor
protocol FilePanePageObject: AnyObject {
    var paneID: PaneID { get }
    var paneAccessibilityIdentifier: String { get }
    var tableAccessibilityIdentifier: String { get }
    var breadcrumbAccessibilityIdentifier: String { get }
    var activeIndicatorAccessibilityIdentifier: String { get }

    @discardableResult
    func navigate(to url: URL) -> Self

    @discardableResult
    func goParent() -> Self

    @discardableResult
    func sort(by key: FileSortKey, ascending: Bool) -> Self

    @discardableResult
    func filter(_ query: String) -> Self
}

/// Shared contract for command-bar page objects.
///
/// Logic-backed robots translate directly to `MainCommand`; future UI-backed
/// pages should drive the command bar through accessibility, menus, or keyboard
/// shortcuts while preserving these action names.
protocol CommandBarPageObject: AnyObject {
    var fieldAccessibilityIdentifier: String { get }
    var listAccessibilityIdentifier: String { get }
    @discardableResult
    func execute(_ action: CommandBarAction) -> Self
}

/// Shared contract for sidebar page objects.
///
/// The unit-test robot uses services and isolated defaults. A future UI-backed
/// page should use sidebar accessibility identifiers while retaining these names.
protocol SidebarPageObject: AnyObject {
    var toggleAccessibilityIdentifier: String { get }
    var listAccessibilityIdentifier: String { get }
    @discardableResult
    func saveBookmarks(_ bookmarks: [Bookmark]) -> Self

    @discardableResult
    func recordRecentLocation(_ url: URL) -> Self
}

/// Shared contract for terminal page objects.
///
/// This remains settings-backed in unit tests because the terminal is
/// experimental and opt-in; future UI pages should still verify that safety gate.
protocol TerminalPageObject: AnyObject {
    var panelAccessibilityIdentifier: String { get }
    var toggleAccessibilityIdentifier: String { get }
    @discardableResult
    func setExperimentalTerminalEnabled(_ enabled: Bool) -> Self

    @discardableResult
    func setVisibleByDefault(_ visible: Bool) -> Self

    @discardableResult
    func acknowledgeWarning() -> Self
}

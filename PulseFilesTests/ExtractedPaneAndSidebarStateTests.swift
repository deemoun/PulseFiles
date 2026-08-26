// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles
@testable import PulseFilesSidebar
@testable import PulseFilesPane

final class ExtractedPaneAndSidebarStateTests: XCTestCase {
    func testQuickSearchCapturesFocusOnlyForActiveSearch() {
        let url = URL(fileURLWithPath: "/tmp/focused")
        var state = QuickSearchState()

        state.transition(from: "", to: "f", focusedURL: url)
        XCTAssertEqual(state.focusedURLBeforeSearch, url)

        state.transition(from: "f", to: "fo", focusedURL: URL(fileURLWithPath: "/tmp/other"))
        XCTAssertEqual(state.focusedURLBeforeSearch, url)

        state.transition(from: "fo", to: "", focusedURL: nil)
        XCTAssertNil(state.focusedURLBeforeSearch)
    }

    func testSelectionRestorationUsesURLsInsteadOfOldRowIndexes() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        var state = FilePaneSelectionRestoration()
        state.record([second])

        XCTAssertEqual(state.rows(in: [second, first], offset: 1) { $0.path }, IndexSet(integer: 1))
        state.prepare(first)
        XCTAssertEqual(state.pendingURL, first)
        XCTAssertEqual(state.consumePending(), first)
        XCTAssertNil(state.pendingURL)
    }

    @MainActor
    func testInspectorGenerationRejectsStaleSelection() {
        let model = SelectionInspectorViewModel()
        let first = model.beginSelection()
        let second = model.beginSelection()

        XCTAssertFalse(model.isCurrent(first))
        XCTAssertTrue(model.isCurrent(second))
    }

    @MainActor
    func testNavigationModelAssemblesOnlyRelevantNonemptySections() {
        let model = SidebarNavigationModel(volumeDiscovery: EmptyVolumeDiscovery())
        let recent = SidebarItem(title: "Recent", url: URL(fileURLWithPath: "/tmp/recent"), symbol: "clock", group: "Recent")

        let sections = model.sections(scratch: [], workspace: [], favorites: [], devices: [], recent: [recent], isRestricted: false)

        XCTAssertEqual(sections.map(\.title), ["Recent"])
        XCTAssertEqual(sections.first?.items.first?.url, recent.url)
    }
}

private struct EmptyVolumeDiscovery: VolumeDiscovering {
    func mountedVolumes() async -> [Volume] { [] }
}

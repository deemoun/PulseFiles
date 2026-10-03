// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesModels

final class PaneTransientStateTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/pulsefiles-transient")
    private func normalize(_ url: URL) -> String { url.standardizedFileURL.path }

    func testPendingSelectionIsConsumedOnlyAfterItAppears() {
        let wanted = root.appendingPathComponent("wanted")
        var state = PaneSelectionRestorationState()
        state.prepare(wanted)

        XCTAssertNil(state.consumePending(ifAvailable: [], normalize: normalize))
        XCTAssertEqual(state.pendingURL, wanted)
        XCTAssertEqual(state.consumePending(ifAvailable: [wanted], normalize: normalize), wanted)
        XCTAssertNil(state.pendingURL)
    }

    func testRecordedSelectionsRestoreByURLAcrossReordering() {
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        var state = PaneSelectionRestorationState()
        state.record([first])

        XCTAssertEqual(state.indexes(in: [second, first], normalize: normalize), IndexSet(integer: 1))
    }

    func testQuickSearchCapturesFocusOnceAndClearsItWhenSearchEnds() {
        let focused = root.appendingPathComponent("focused")
        var state = PaneQuickSearchState()
        state.transition(from: "", to: "f", focusedURL: focused)
        state.transition(from: "f", to: "fo", focusedURL: root.appendingPathComponent("other"))
        XCTAssertEqual(state.focusedURLBeforeSearch, focused)

        state.transition(from: "fo", to: "", focusedURL: focused)
        XCTAssertNil(state.focusedURLBeforeSearch)
    }
}

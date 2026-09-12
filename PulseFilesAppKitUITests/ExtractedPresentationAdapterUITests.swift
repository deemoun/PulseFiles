// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles
import PulseFilesAppCoordination

@MainActor
final class ExtractedPresentationAdapterUITests: XCTestCase {
    func testPaneArrangementAdapterInstallsRoutedViews() {
        let root = NSSplitView()
        let content = NSSplitView()
        let panes = NSSplitView()
        let left = NSView()
        let right = NSView()
        let adapter = PaneArrangementCoordinator(
            inputs: .init(root: root, content: content, panes: panes, paneView: { $0 == .left ? left : right }, sidebarInstalled: { false }),
            persistSidebarWidth: {}
        )

        adapter.installAsDelegate()
        adapter.apply(.init(singlePane: true, focusedPane: .right))

        XCTAssertTrue(root.delegate === adapter)
        XCTAssertTrue(content.delegate === adapter)
        XCTAssertTrue(panes.delegate === adapter)
        XCTAssertEqual(panes.arrangedSubviews, [right])
    }

    func testDeletePresentationProducesBoundedItemList() {
        let urls = (0..<10).map { URL(fileURLWithPath: "/tmp/item\($0)") }
        let detail = SelectionInformationUIAdapter.deleteDetail(permanently: true, urls: urls)
        XCTAssertTrue(detail.contains("item0"))
        XCTAssertTrue(detail.contains("...and 2 more"))
    }
}

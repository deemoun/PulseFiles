// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
import PulseFilesModels
@testable import PulseFilesWorkflows

final class MainCommandRouterTests: XCTestCase {
    private let router = MainCommandRouter()

    func testCopyRoutesSelectionBetweenPanesWithoutServices() {
        let selected = URL(fileURLWithPath: "/sandbox/left/report.pdf")
        let destination = URL(fileURLWithPath: "/sandbox/right", isDirectory: true)
        let state = makeState(leftSelection: [selected], rightDirectory: destination)

        XCTAssertEqual(
            router.route(.copy, in: state),
            .crossPane(command: .copy, sourcePane: .left, destinationPane: .right, sourceURLs: [selected], destinationDirectory: destination)
        )
    }

    func testCopyRejectsSelectionDeniedBySandboxDecision() {
        let selected = URL(fileURLWithPath: "/outside/secret.txt")
        let state = makeState(leftSelection: [selected], sandboxAllowsSelectedURLs: false)

        XCTAssertEqual(router.route(.copy, in: state), .disabled(command: .copy, reason: .sandboxRejectedSelection))
    }

    func testSearchResultRoutingUsesModelValueWithoutServices() {
        let root = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let item = DescendantSearchItem(
            url: root.appendingPathComponent("gone.txt"),
            name: "gone.txt",
            pathContext: root.path,
            typeDescription: "File",
            isDirectory: false,
            isSymbolicLink: false
        )

        XCTAssertEqual(
            SearchResultActionRouter().route(.open, item: item, root: root, canAccess: { _ in true }, itemExists: false),
            .unavailable
        )
    }

    private func makeState(
        leftSelection: [URL] = [],
        rightDirectory: URL = URL(fileURLWithPath: "/sandbox/right", isDirectory: true),
        sandboxAllowsSelectedURLs: Bool = true
    ) -> MainCommandRoutingState {
        MainCommandRoutingState(
            leftPane: MainCommandRoutingPane(
                id: .left,
                currentDirectory: URL(fileURLWithPath: "/sandbox/left", isDirectory: true),
                selectedURLs: leftSelection,
                focusedURL: leftSelection.first
            ),
            rightPane: MainCommandRoutingPane(id: .right, currentDirectory: rightDirectory),
            sandboxAllowsSelectedURLs: sandboxAllowsSelectedURLs
        )
    }
}

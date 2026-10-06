// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFilesPane

@MainActor
final class BreadcrumbViewUITests: XCTestCase {
    func testProtectedRootMarkerIsHiddenAndClickTargetsStayProtected() {
        let view = BreadcrumbView()
        let directory = URL(fileURLWithPath: "/.nofollow/Users/example/Desktop", isDirectory: true)
        view.configure(url: directory)
        let buttons = view.arrangedSubviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.map(\.title), ["/", "Users", "example", "Desktop"])
        var selected: URL?
        view.onSelect = { selected = $0 }
        for (button, expected) in zip(buttons, ["/.nofollow/", "/.nofollow/Users/", "/.nofollow/Users/example/", directory.path + "/"]) {
            button.performClick(nil)
            XCTAssertEqual(selected?.absoluteString, URL(fileURLWithPath: expected, isDirectory: true).absoluteString)
        }
        XCTAssertEqual(view.url, directory)
    }

    func testProtectedRootAndLiteralStubRemainDistinct() {
        let view = BreadcrumbView()
        view.configure(url: URL(fileURLWithPath: "/.nofollow/", isDirectory: true))
        XCTAssertEqual(view.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }, ["/"])
        view.configure(url: URL(fileURLWithPath: "/.nofollow", isDirectory: false))
        XCTAssertEqual(view.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }, ["/", ".nofollow"])
    }

    func testOrdinaryFoldersNamedNofollowRemainVisible() {
        let view = BreadcrumbView()
        view.configure(url: URL(fileURLWithPath: "/Users/example/.nofollow/Desktop", isDirectory: true))
        XCTAssertEqual(view.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }, ["/", "Users", "example", ".nofollow", "Desktop"])
        view.configure(url: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true))
        XCTAssertEqual(view.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }, ["/", "Users", "example", "Desktop"])
    }
}

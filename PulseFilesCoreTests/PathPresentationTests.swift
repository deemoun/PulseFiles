// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesUtilities

final class PathPresentationTests: XCTestCase {
    func testProtectedHomePathIsCleanedBeforeHomeAbbreviation() {
        let url = URL(fileURLWithPath: "/.nofollow/Users/example/Desktop", isDirectory: true)
        XCTAssertEqual(PathUtilities.displayPath(for: url, homeDirectory: "/Users/example"), "~/Desktop")
        XCTAssertEqual(PathUtilities.displayPath(for: url), "/Users/example/Desktop")
        XCTAssertEqual(url.path, "/.nofollow/Users/example/Desktop")
    }

    func testHomeAbbreviationOnlyMatchesTheLeadingDirectory() {
        for path in ["/Users/example-other/Desktop", "/Volumes/Backup/Users/example/Desktop"] {
            XCTAssertEqual(PathUtilities.displayPath(for: URL(fileURLWithPath: path), homeDirectory: "/Users/example"), path)
        }
        XCTAssertEqual(PathUtilities.displayPath(for: URL(fileURLWithPath: "/Users/example"), homeDirectory: "/Users/example"), "~")
    }

    func testProtectedRootAndLiteralFoldersRemainDistinct() {
        XCTAssertEqual(PathUtilities.displayPath(for: URL(fileURLWithPath: "/.nofollow/", isDirectory: true)), "/")
        XCTAssertEqual(PathUtilities.displayPath(for: URL(fileURLWithPath: "/.nofollow", isDirectory: false)), "/.nofollow")
        let nested = URL(fileURLWithPath: "/Users/example/.nofollow/Desktop", isDirectory: true)
        XCTAssertEqual(PathUtilities.displayPath(for: nested, homeDirectory: "/Users/example"), "~/.nofollow/Desktop")
    }
}

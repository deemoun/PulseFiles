// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class TerminalServiceTests: XCTestCase {
    func testSanitizedEnvironmentProvidesTermWhenMissing() {
        let service = TerminalService()

        let environment = service.sanitizedEnvironment(from: [:])

        XCTAssertEqual(environment["TERM"], "xterm-256color")
    }

    func testSanitizedEnvironmentReplacesDumbTerm() {
        let service = TerminalService()

        let environment = service.sanitizedEnvironment(from: ["TERM": "dumb"])

        XCTAssertEqual(environment["TERM"], "xterm-256color")
    }

    func testSanitizedEnvironmentPreservesExistingTerm() {
        let service = TerminalService()

        let environment = service.sanitizedEnvironment(from: ["TERM": "vt100"])

        XCTAssertEqual(environment["TERM"], "vt100")
    }

    func testSanitizedEnvironmentProvidesUtf8LocaleDefaults() {
        let service = TerminalService()

        let environment = service.sanitizedEnvironment(from: [:])

        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "en_US.UTF-8")
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFilesServices
@testable import PulseFilesModels
@testable import PulseFilesUtilities

final class SymbolicLinkResolutionServiceTests: XCTestCase {
    func testResolvesAbsoluteAndRelativeTargetsOneHop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.txt")
        try Data().write(to: target)
        let relativeLink = root.appendingPathComponent("relative-link")
        let absoluteLink = root.appendingPathComponent("absolute-link")
        try FileManager.default.createSymbolicLink(atPath: relativeLink.path, withDestinationPath: "target.txt")
        try FileManager.default.createSymbolicLink(at: absoluteLink, withDestinationURL: target)

        let service = SymbolicLinkResolutionService()
        XCTAssertEqual(try service.resolveOneHop(relativeLink), target.standardizedFileURL)
        XCTAssertEqual(try service.resolveOneHop(absoluteLink), target.standardizedFileURL)
    }

    func testRejectsBrokenLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("broken-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")

        XCTAssertThrowsError(try SymbolicLinkResolutionService().resolveOneHop(link)) {
            XCTAssertEqual($0 as? SymbolicLinkResolutionError, .targetDoesNotExist)
        }
    }
}

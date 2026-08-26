// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class SystemFileSizeServiceTests: XCTestCase {
    private let service = SystemFileSizeService()

    func testReturnsTheLogicalSizeReportedByLstatForAFile() throws {
        let file = try makeTemporaryDirectory().appendingPathComponent("report.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try Data(repeating: 7, count: 321).write(to: file)

        XCTAssertEqual(try service.size(of: file), 321)
    }

    func testRecursivelyReturnsTheCombinedSizeOfFolderContents() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: directory.appendingPathComponent("first.bin"))
        try Data(repeating: 2, count: 64).write(to: nested.appendingPathComponent("second.bin"))

        XCTAssertEqual(try service.size(of: directory), 192)
    }

    func testDoesNotFollowSymbolicLinksWhenMeasuringFolders() throws {
        let directory = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data(repeating: 3, count: 4_096).write(to: outside.appendingPathComponent("outside.bin"))
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("outside-link").path, withDestinationPath: outside.path)

        let size = try service.size(of: directory)
        XCTAssertLessThan(size, 4_096)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

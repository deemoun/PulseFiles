// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesServices
@testable import PulseFilesCapabilities

final class PTYTerminalProcessTests: XCTestCase {
    func testChildWorkingDirectoryAndArgumentsRemainLiteral() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("folder with spaces; $(touch injected)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = PTYTerminalProcess()
        let output = LockedTerminalOutput()
        let exited = expectation(description: "child exits")
        process.outputHandler = { output.append($0) }
        process.terminationHandler = { _ in exited.fulfill() }
        let literal = "argument with spaces; $(touch injected)"
        process.configure(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s\\n' \"$PWD\" \"$1\"; sleep 0.1", "test", literal],
            environment: ["PATH": "/usr/bin:/bin"], currentDirectoryURL: folder)
        try process.run()
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(output.text.contains(folder.resolvingSymlinksInPath().path))
        XCTAssertTrue(output.text.contains(literal))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("injected").path))
    }

    func testMissingWorkingDirectoryDoesNotExecuteRequestedCommand() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let process = PTYTerminalProcess()
        let output = LockedTerminalOutput()
        let exited = expectation(description: "directory failure exits")
        process.outputHandler = { output.append($0) }
        process.terminationHandler = { _ in exited.fulfill() }
        process.configure(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf REQUESTED_COMMAND_EXECUTED"],
            environment: ["PATH": "/usr/bin:/bin"], currentDirectoryURL: missing)
        try process.run()
        wait(for: [exited], timeout: 5)
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertFalse(output.text.contains("REQUESTED_COMMAND_EXECUTED"))
    }
}

private final class LockedTerminalOutput {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; data.append(chunk) }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFiles

final class SandboxFixture {
    let temporaryDirectory: TemporaryDirectoryFixture
    let root: URL
    let allowedDirectory: URL
    let externalDirectory: URL
    let policy: SandboxFileAccessPolicy
    let unrestrictedPolicy: SandboxFileAccessPolicy

    init(testCase: XCTestCase? = nil) throws {
        temporaryDirectory = try TemporaryDirectoryFixture(named: "PulseFilesSandboxTests", testCase: testCase)
        root = try temporaryDirectory.folder("AllowedSandbox")
        allowedDirectory = try temporaryDirectory.folder("AllowedSandbox/Allowed")
        externalDirectory = try temporaryDirectory.folder("External")
        policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
        unrestrictedPolicy = SandboxFileAccessPolicy(isEnabled: false, rootURL: root)
    }

    @discardableResult
    func allowedFile(_ relativePath: String = "Allowed/File.txt", contents: String = "allowed") throws -> URL {
        try temporaryDirectory.file("AllowedSandbox/\(relativePath)", contents: contents)
    }

    @discardableResult
    func externalFile(_ relativePath: String = "Outside.txt", contents: String = "external") throws -> URL {
        try temporaryDirectory.file("External/\(relativePath)", contents: contents)
    }

    func fileOperationService(fileManager: FileManager = .default) -> FileOperationService {
        FileOperationService(fileManager: fileManager, accessPolicy: policy)
    }
}

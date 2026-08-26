// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFiles

final class TemporaryDirectoryFixture {
    let root: URL
    private let fileManager: FileManager

    init(
        named name: String = "PulseFilesTests",
        fileManager: FileManager = .default,
        testCase: XCTestCase? = nil
    ) throws {
        self.fileManager = fileManager
        root = fileManager.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        testCase?.addTeardownBlock { [fileManager, root] in
            if fileManager.fileExists(atPath: root.path) {
                try? fileManager.removeItem(at: root)
            }
        }
    }

    @discardableResult
    func folder(_ relativePath: String) throws -> URL {
        let url = path(relativePath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ relativePath: String, contents: String = "", encoding: String.Encoding = .utf8) throws -> URL {
        let url = path(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: encoding)
        return url
    }

    @discardableResult
    func hiddenFile(_ relativePath: String, contents: String = "") throws -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let last = components.last else {
            return try file(".hidden", contents: contents)
        }
        let hiddenName = last.hasPrefix(".") ? last : ".\(last)"
        let hiddenPath = (components.dropLast() + [hiddenName]).joined(separator: "/")
        return try file(hiddenPath, contents: contents)
    }

    func path(_ relativePath: String, isDirectory: Bool = false) -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.enumerated().reduce(root) { partialResult, entry in
            let isLastComponent = entry.offset == components.count - 1
            return partialResult.appendingPathComponent(entry.element, isDirectory: isDirectory && isLastComponent)
        }
    }

    func cleanup() throws {
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }
}

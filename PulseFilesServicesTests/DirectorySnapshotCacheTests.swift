// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
@testable import PulseFilesServices
import XCTest

@MainActor
final class DirectorySnapshotCacheTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/cache-directory")
    private let metadata = DirectorySnapshotMetadata(resourceIdentifier: "id", changeDate: nil)

    func testCacheHitRefreshesRecency() {
        let cache = DirectorySnapshotCache(limits: .init(maximumEntryCount: 2, maximumItemCount: 10))
        let first = key(directory: directory)
        let second = key(directory: directory.appendingPathComponent("two"))
        let third = key(directory: directory.appendingPathComponent("three"))
        cache.store([item("first")], metadata: metadata, for: first)
        cache.store([item("second")], metadata: metadata, for: second)

        XCTAssertNotNil(cache.snapshot(for: first))
        cache.store([item("third")], metadata: metadata, for: third)

        XCTAssertNotNil(cache.snapshot(for: first))
        XCTAssertNil(cache.snapshot(for: second))
        XCTAssertNotNil(cache.snapshot(for: third))
    }

    func testSortAndHiddenFileVariantsAreIndependent() {
        let cache = DirectorySnapshotCache(limits: .init(maximumEntryCount: 4, maximumItemCount: 10))
        let name = key(directory: directory)
        let size = key(directory: directory, sort: .init(key: .size, ascending: false))
        let hidden = key(directory: directory, includesHiddenFiles: true)
        cache.store([item("name")], metadata: metadata, for: name)
        cache.store([item("size")], metadata: metadata, for: size)
        cache.store([item("hidden")], metadata: metadata, for: hidden)

        XCTAssertEqual(cache.snapshot(for: name)?.items.first?.filename, "name")
        XCTAssertEqual(cache.snapshot(for: size)?.items.first?.filename, "size")
        XCTAssertEqual(cache.snapshot(for: hidden)?.items.first?.filename, "hidden")
    }

    func testDirectoryInvalidationRemovesEveryVariantOnlyForThatDirectory() {
        let cache = DirectorySnapshotCache()
        let visible = key(directory: directory)
        let hidden = key(directory: directory, includesHiddenFiles: true)
        let other = key(directory: directory.appendingPathComponent("other"))
        cache.store([item("visible")], metadata: metadata, for: visible)
        cache.store([item("hidden")], metadata: metadata, for: hidden)
        cache.store([item("other")], metadata: metadata, for: other)

        cache.invalidate(directory: directory)

        XCTAssertNil(cache.snapshot(for: visible))
        XCTAssertNil(cache.snapshot(for: hidden))
        XCTAssertNotNil(cache.snapshot(for: other))
    }

    func testItemBudgetEvictsLeastRecentlyUsedEntries() {
        let cache = DirectorySnapshotCache(limits: .init(maximumEntryCount: 10, maximumItemCount: 3))
        let first = key(directory: directory)
        let second = key(directory: directory.appendingPathComponent("two"))
        cache.store([item("a"), item("b")], metadata: metadata, for: first)
        cache.store([item("c"), item("d")], metadata: metadata, for: second)

        XCTAssertNil(cache.snapshot(for: first))
        XCTAssertNotNil(cache.snapshot(for: second))
    }

    func testClearRemovesSnapshotsForMemoryPressure() {
        let cache = DirectorySnapshotCache()
        let cachedKey = key(directory: directory)
        cache.store([item("cached")], metadata: metadata, for: cachedKey)

        cache.clear()

        XCTAssertNil(cache.snapshot(for: cachedKey))
    }

    private func key(
        directory: URL,
        includesHiddenFiles: Bool = false,
        sort: FileSortDescriptor = .init()
    ) -> DirectorySnapshotCache.Key {
        .init(directory: directory, includesHiddenFiles: includesHiddenFiles, sort: sort)
    }

    private func item(_ name: String) -> FileItem {
        FileItem(
            url: directory.appendingPathComponent(name), filename: name, displayName: name,
            fileExtension: "", fileType: .file, isDirectory: false, isSymbolicLink: false,
            isHidden: false, size: 1, creationDate: nil, modificationDate: nil,
            posixPermissions: nil, owner: nil, group: nil, typeDescription: "File",
            localizedTypeDescription: "File", iconKey: .init(fileType: .file, fileExtension: "")
        )
    }
}

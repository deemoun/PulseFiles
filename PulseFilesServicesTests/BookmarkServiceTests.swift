// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFilesServices
@testable import PulseFilesModels
@testable import PulseFilesUtilities

final class BookmarkServiceTests: XCTestCase {
    func testBookmarkPersistenceRoundTrip() {
        let suiteName = "PulseFilesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = BookmarkService(defaults: defaults)
        let bookmarks = [Bookmark(title: "Home", url: URL(fileURLWithPath: "/Users/example"))]

        service.save(bookmarks)

        XCTAssertEqual(service.load(), bookmarks)
    }

    func testBookmarkMutationsPreserveExplicitOrder() {
        let suiteName = "PulseFilesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = BookmarkService(defaults: defaults)
        let first = service.add(url: URL(fileURLWithPath: "/first"), title: "First")[0]
        let second = service.add(url: URL(fileURLWithPath: "/second"), title: "Second")[1]

        XCTAssertEqual(service.move(id: second.id, to: 0).map(\.id), [second.id, first.id])
        XCTAssertEqual(service.rename(id: first.id, title: "Renamed").map(\.title), ["Second", "Renamed"])
        XCTAssertEqual(service.remove(id: second.id), [Bookmark(id: first.id, title: "Renamed", url: first.url)])
    }
}

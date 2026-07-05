import Foundation
import XCTest
@testable import PulseFiles

final class SidebarRobot {
    private let bookmarkService: BookmarkService
    private let recentLocationService: RecentLocationService

    init(bookmarkService: BookmarkService, recentLocationService: RecentLocationService) {
        self.bookmarkService = bookmarkService
        self.recentLocationService = recentLocationService
    }

    @discardableResult
    func saveBookmarks(_ bookmarks: [Bookmark]) -> Self {
        bookmarkService.save(bookmarks)
        return self
    }

    @discardableResult
    func recordRecentLocation(_ url: URL) -> Self {
        recentLocationService.record(url)
        return self
    }

    @discardableResult
    func expectBookmarks(_ expected: [Bookmark], file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(bookmarkService.load(), expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectRecentLocations(_ expected: [URL], file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(recentLocationService.locations, expected, file: file, line: line)
        return self
    }
}

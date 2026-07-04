import XCTest
@testable import PulseFiles

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
}

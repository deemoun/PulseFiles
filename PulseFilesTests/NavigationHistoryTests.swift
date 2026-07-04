import XCTest
@testable import PulseFiles

final class NavigationHistoryTests: XCTestCase {
    func testBackAndForwardHistory() {
        let home = URL(fileURLWithPath: "/Users/example")
        let downloads = home.appendingPathComponent("Downloads")
        let documents = home.appendingPathComponent("Documents")
        var history = NavigationHistory(initialURL: home)

        history.visit(downloads)
        history.visit(documents)

        XCTAssertEqual(history.goBack(), downloads)
        XCTAssertEqual(history.goBack(), home)
        XCTAssertNil(history.goBack())
        XCTAssertEqual(history.goForward(), downloads)
        XCTAssertEqual(history.goForward(), documents)
    }

    func testVisitingCurrentURLDoesNotDuplicateHistory() {
        let url = URL(fileURLWithPath: "/tmp")
        var history = NavigationHistory(initialURL: url)
        history.visit(url)
        XCTAssertFalse(history.canGoBack)
    }
}

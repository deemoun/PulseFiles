import XCTest
@testable import PulseFiles

final class QuickLocationTests: XCTestCase {
    func testAssemblyPreservesBookmarkOrderAndAvailability() {
        let active = URL(fileURLWithPath: "/work/project", isDirectory: true)
        var history = NavigationHistory(initialURL: active)
        history.visit(URL(fileURLWithPath: "/visited", isDirectory: true))
        let denied = Bookmark(title: "Denied", url: URL(fileURLWithPath: "/denied"))
        let stale = Bookmark(title: "Stale", url: URL(fileURLWithPath: "/stale"))

        let entries = QuickLocationAssembler.assemble(
            activeDirectory: active, history: history, bookmarks: [denied, stale], recent: [], volumes: [],
            scratchDirectory: nil, oppositeDirectory: URL(fileURLWithPath: "/other"),
            canAccess: { $0.path != "/denied" }, exists: { $0.path != "/stale" }
        )
        let favorites = entries.filter { $0.section == .favorites }
        XCTAssertEqual(favorites.map(\.id), ["bookmark:\(denied.id.uuidString)", "bookmark:\(stale.id.uuidString)"])
        XCTAssertEqual(favorites.map(\.availability), [.accessDenied, .unavailable])
        XCTAssertEqual(entries.last?.id, "opposite")
    }

    func testStablePathIdentityDoesNotDependOnDisplayTitle() {
        let url = URL(fileURLWithPath: "/recent")
        let entries = QuickLocationAssembler.assemble(activeDirectory: URL(fileURLWithPath: "/a"), history: NavigationHistory(), bookmarks: [], recent: [url], volumes: [], scratchDirectory: nil, oppositeDirectory: nil, canAccess: { _ in true }, exists: { _ in true })
        XCTAssertEqual(entries.first(where: { $0.section == .recent })?.id, "recent:/recent")
    }
}

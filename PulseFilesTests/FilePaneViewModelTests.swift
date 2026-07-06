import XCTest
@testable import PulseFiles

@MainActor
final class FilePaneViewModelTests: XCTestCase {
    func testInitialLoadReadsFixtureDirectoryContents() async throws {
        let fixture = try PaneFixture(testCase: self)
        try fixture.sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Welcome.txt", contents: "hello")
        try fixture.sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Documents")

        await load(fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.currentDirectory, fixture.root)
        XCTAssertEqual(fixture.viewModel.visibleItems.map(\.displayName), ["Documents", "Welcome.txt"])
        XCTAssertFalse(fixture.viewModel.isLoading)
        XCTAssertNil(fixture.viewModel.errorMessage)
    }

    func testViewModelPreservesFolderFirstOrdering() async throws {
        let fixture = try PaneFixture(sort: .init(key: .name, ascending: true), testCase: self)
        try fixture.makeFoldersFirstLayout()

        await load(fixture.viewModel)

        XCTAssertEqual(
            fixture.viewModel.visibleItems.map(\.displayName),
            ["Alpha Folder", "Zebra Folder", "alpha.txt", "beta.txt"]
        )
        XCTAssertEqual(fixture.viewModel.visibleItems.prefix(2).map(\.isDirectory), [true, true])
    }

    func testSearchFilteringShowsMatchesHidesNonMatchesAndOmitsParentRow() async throws {
        let fixture = try PaneFixture(testCase: self)
        try fixture.makeSearchLayout()

        await load(fixture.viewModel)
        fixture.viewModel.setSearchQuery("report")

        let visibleNames = fixture.viewModel.visibleItems.map(\.displayName)
        XCTAssertEqual(visibleNames, ["Reports Archive", "Quarterly Report.txt"])
        XCTAssertTrue(visibleNames.contains("Quarterly Report.txt"))
        XCTAssertFalse(visibleNames.contains("Notes.md"))
        XCTAssertFalse(visibleNames.contains(".."))
    }

    func testHiddenFilesAreExcludedByDefaultWhenConfiguredOff() async throws {
        let fixture = try PaneFixture(showsHiddenFiles: false, testCase: self)
        try fixture.makeHiddenFilesLayout()

        await load(fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.visibleItems.map(\.displayName), ["Visible.txt"])
        XCTAssertFalse(fixture.viewModel.visibleItems.contains { $0.isHidden })
    }

    func testHiddenFilesAppearWhenEnabled() async throws {
        let fixture = try PaneFixture(showsHiddenFiles: true, testCase: self)
        try fixture.makeHiddenFilesLayout()

        await load(fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.visibleItems.map(\.displayName), [".env", "Visible.txt"])
        XCTAssertTrue(fixture.viewModel.visibleItems.contains { $0.displayName == ".env" && $0.isHidden })
    }

    func testParentNavigationWorksInsideAllowedRoot() async throws {
        let fixture = try PaneFixture(testCase: self)
        let child = try fixture.sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Child")
        fixture.viewModel.navigate(to: child)
        await waitUntilLoaded(fixture.viewModel)

        fixture.viewModel.goParent()
        await waitUntilLoaded(fixture.viewModel)

        XCTAssertEqual(fixture.viewModel.currentDirectory, fixture.root)
    }

    func testParentNavigationCannotEscapeSandboxBoundary() async throws {
        let fixture = try PaneFixture(testCase: self)
        await load(fixture.viewModel)

        fixture.viewModel.goParent()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fixture.viewModel.currentDirectory, fixture.root)
        XCTAssertTrue(fixture.accessPolicy.canAccess(fixture.viewModel.currentDirectory))
        XCTAssertFalse(fixture.accessPolicy.canAccess(fixture.root.deletingLastPathComponent().deletingLastPathComponent()))
    }

    private func load(_ viewModel: FilePaneViewModel) async {
        await withCheckedContinuation { continuation in
            viewModel.loadCurrentDirectory {
                continuation.resume()
            }
        }
    }

    private func waitUntilLoaded(_ viewModel: FilePaneViewModel) async {
        while viewModel.isLoading {
            await Task.yield()
        }
    }
}

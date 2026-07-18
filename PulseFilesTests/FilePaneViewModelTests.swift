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

    func testFailedNavigationToMissingFolderPreservesCurrentDirectoryAndItems() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        let rootItem = TestFileSystem.item(named: "Keep.txt", in: sandbox.allowedDirectory)
        let missing = sandbox.allowedDirectory.appendingPathComponent("Missing", isDirectory: true)
        fileSystem.setItems([rootItem], for: sandbox.allowedDirectory)
        fileSystem.setError(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
            for: missing
        )
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        await load(viewModel)
        viewModel.navigate(to: missing)
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Keep.txt"])
        XCTAssertEqual(viewModel.loadFailure?.directory, missing)
        XCTAssertTrue(viewModel.loadFailure?.isMissingDirectory == true)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testFailedOutsideSandboxLoadPreservesSafeState() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = FileSystemService(accessPolicy: sandbox.policy)
        let allowedFile = try sandbox.allowedFile("Allowed.txt", contents: "allowed")
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.unrestrictedPolicy
        )

        await load(viewModel)
        viewModel.navigate(to: sandbox.externalDirectory)
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertEqual(viewModel.visibleItems.map(\.url), [allowedFile])
        XCTAssertEqual(viewModel.loadFailure?.directory, sandbox.externalDirectory)
        XCTAssertTrue(viewModel.loadFailure?.isOutsideSandbox == true)
        XCTAssertNotNil(viewModel.errorMessage)
    }


    func testRapidNavigationKeepsLatestSuccessfulLoadResult() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let firstDirectory = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/First")
        let secondDirectory = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let fileSystem = DelayedFileSystem()
        fileSystem.setItems([TestFileSystem.item(named: "Old.txt", in: firstDirectory)], for: firstDirectory, delay: 200_000_000)
        fileSystem.setItems([TestFileSystem.item(named: "New.txt", in: secondDirectory)], for: secondDirectory, delay: 10_000_000)
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        viewModel.navigate(to: firstDirectory)
        viewModel.navigate(to: secondDirectory)
        await waitUntilLoaded(viewModel)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.currentDirectory, secondDirectory)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["New.txt"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCurrentLoadCancellationClearsLoadingAndNotifiesChange() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = DelayedFileSystem()
        fileSystem.setError(CancellationError(), for: sandbox.allowedDirectory, delay: 10_000_000)
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )
        var changeCount = 0
        viewModel.onChange = { changeCount += 1 }

        viewModel.loadCurrentDirectory()
        await waitUntilLoaded(viewModel)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertGreaterThanOrEqual(changeCount, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.loadFailure)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testUnavailableCurrentDirectoryFallsBackToAccessibleDirectory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let removedDirectory = sandbox.allowedDirectory.appendingPathComponent("RemovedVolume", isDirectory: true)
        let fileSystem = TestFileSystem()
        let viewModel = FilePaneViewModel(
            initialDirectory: removedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        let didFallBack = viewModel.fallBackIfCurrentDirectoryIsUnavailable(
            directoryExists: { $0 != removedDirectory },
            preferredFallback: sandbox.allowedDirectory
        )
        await waitUntilLoaded(viewModel)

        XCTAssertTrue(didFallBack)
        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
        XCTAssertEqual(fileSystem.requests.last?.url, sandbox.allowedDirectory)
    }

    func testVolumeChangeRefreshesReachableCurrentDirectory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        viewModel.refreshAfterVolumeChange(
            directoryExists: { $0 == sandbox.allowedDirectory },
            preferredFallback: sandbox.root
        )
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertEqual(fileSystem.requests.last?.url, sandbox.allowedDirectory)
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


private final class DelayedFileSystem: FileSystemServicing {
    private var responses: [URL: (items: [FileItem], error: Error?, delay: UInt64)] = [:]

    func setItems(_ items: [FileItem], for directory: URL, delay: UInt64) {
        responses[directory] = (items: items, error: nil, delay: delay)
    }

    func setError(_ error: Error, for directory: URL, delay: UInt64) {
        responses[directory] = (items: [], error: error, delay: delay)
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> [FileItem] {
        let response = responses[url] ?? (items: [], error: nil, delay: 0)
        if response.delay > 0 {
            try? await Task.sleep(nanoseconds: response.delay)
        }
        if let error = response.error {
            throw error
        }
        let visibleItems = includingHidden ? response.items : response.items.filter { !$0.isHidden }
        return FileSystemService.sorted(visibleItems, descriptor: sort)
    }
}

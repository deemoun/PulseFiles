import XCTest
@testable import PulseFiles

@MainActor
final class FilePaneViewModelTests: XCTestCase {
    func testDirectoryReadsRunWhilePersistedGrantScopeIsActive() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let defaults = try IsolatedDefaultsFixture(prefix: "PaneScopedReads", testCase: self)
        defer { defaults.cleanup() }
        var activeScopes = 0
        let grants = FolderAccessGrantService(
            defaults: defaults.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in activeScopes += 1; return true },
            stopSecurityScopedAccess: { _ in activeScopes -= 1 }
        )
        try grants.grantAccess(to: sandbox.externalDirectory)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandbox.root, grantService: grants)
        let fileSystem = ScopeAssertingFileSystem { activeScopes > 0 }
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.externalDirectory, fileSystem: fileSystem, accessPolicy: policy)

        await load(viewModel)

        XCTAssertTrue(fileSystem.allReadsHadActiveScope)
        XCTAssertEqual(activeScopes, 0)
    }
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

    func testParentNavigationAvailabilityUsesTheAccessPolicy() throws {
        let fixture = try PaneFixture(testCase: self)
        let parent = fixture.root.deletingLastPathComponent()

        XCTAssertFalse(fixture.viewModel.canNavigate(to: parent))
        XCTAssertTrue(fixture.viewModel.canNavigate(to: fixture.root))
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

    func testExternalChangesDuringLoadCoalesceIntoOneNewestRefresh() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = DelayedFileSystem()
        let initialItems = [TestFileSystem.item(named: "Before.txt", in: sandbox.allowedDirectory)]
        let newestItems = [TestFileSystem.item(named: "Newest.txt", in: sandbox.allowedDirectory)]
        fileSystem.setItems(initialItems, for: sandbox.allowedDirectory, delay: 100_000_000)
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        viewModel.loadCurrentDirectory()
        await waitUntilRequestCount(fileSystem, isAtLeast: 1)
        fileSystem.setItems(newestItems, for: sandbox.allowedDirectory, delay: 10_000_000)

        viewModel.reloadAfterExternalDirectoryChange()
        viewModel.reloadAfterExternalDirectoryChange()
        viewModel.reloadAfterExternalDirectoryChange()

        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Newest.txt"])
        XCTAssertEqual(fileSystem.requestCount, 2)
        XCTAssertFalse(viewModel.isLoading)
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

    func testExternalRevalidationRefreshesReachableCurrentDirectory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy
        )

        viewModel.reloadAfterExternalDirectoryChange()
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertEqual(fileSystem.requests.last?.url, sandbox.allowedDirectory)
    }

    func testUnchangedRefreshValidatesSnapshotWithoutEnumeratingAgain() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        fileSystem.setItems([TestFileSystem.item(named: "Cached.txt", in: sandbox.allowedDirectory)], for: sandbox.allowedDirectory)
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)

        await load(viewModel)
        await load(viewModel)

        XCTAssertEqual(fileSystem.requests.count, 1)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Cached.txt"])
    }

    func testDirectoryMetadataMutationInvalidatesSnapshotAndEnumeratesAgain() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        fileSystem.setItems([TestFileSystem.item(named: "Before.txt", in: sandbox.allowedDirectory)], for: sandbox.allowedDirectory)
        fileSystem.setMetadata(.init(resourceIdentifier: "directory", changeDate: Date(timeIntervalSinceReferenceDate: 1)), for: sandbox.allowedDirectory)
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)

        await load(viewModel)
        fileSystem.setItems([TestFileSystem.item(named: "After.txt", in: sandbox.allowedDirectory)], for: sandbox.allowedDirectory)
        fileSystem.setMetadata(.init(resourceIdentifier: "directory", changeDate: Date(timeIntervalSinceReferenceDate: 2)), for: sandbox.allowedDirectory)
        await load(viewModel)

        XCTAssertEqual(fileSystem.requests.count, 2)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["After.txt"])
    }

    func testPartialMetadataRefreshRetainsCompleteListingAndSchedulesRetry() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        let retained = TestFileSystem.item(named: "Retained.txt", in: sandbox.allowedDirectory)
        let unreadable = TestFileSystem.item(named: "Unreadable.txt", in: sandbox.allowedDirectory)
        fileSystem.setItems([retained, unreadable], for: sandbox.allowedDirectory)
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)

        await load(viewModel)
        fileSystem.setItems([retained], for: sandbox.allowedDirectory)
        fileSystem.setItemReadFailures([
            DirectoryItemReadFailure(
                url: unreadable.url,
                error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            )
        ], for: sandbox.allowedDirectory)

        viewModel.reloadAfterExternalDirectoryChange()
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Retained.txt", "Unreadable.txt"])
        XCTAssertEqual(viewModel.partialRefreshFailure?.failures.map(\.url), [unreadable.url])
        XCTAssertTrue(viewModel.isPartialRefreshRetryScheduled)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailedSnapshotValidationDoesNotReportStaleContentsAsCurrent() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = TestFileSystem()
        fileSystem.setItems([TestFileSystem.item(named: "Stale.txt", in: sandbox.allowedDirectory)], for: sandbox.allowedDirectory)
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)

        await load(viewModel)
        fileSystem.setMetadataError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError), for: sandbox.allowedDirectory)
        var didReportLoaded = false
        viewModel.loadCurrentDirectory { didReportLoaded = true }
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(fileSystem.requests.count, 1)
        XCTAssertFalse(didReportLoaded)
        XCTAssertNotNil(viewModel.loadFailure)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Stale.txt"])
    }

    func testTimedOutReadRetainsCompleteListingAndCanRetry() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = NeverCompletingFileSystem()
        let retained = TestFileSystem.item(named: "Retained.txt", in: sandbox.allowedDirectory)
        let recovered = TestFileSystem.item(named: "Recovered.txt", in: sandbox.allowedDirectory)
        fileSystem.items = [retained]
        let viewModel = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy,
            directoryLoadTimeout: 0.01
        )

        await load(viewModel)
        fileSystem.neverCompletes = true
        viewModel.loadCurrentDirectory(forceRefresh: true)
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Retained.txt"])
        XCTAssertTrue(viewModel.loadFailure?.isTimedOut == true)
        XCTAssertTrue(viewModel.loadFailure?.isRetryable == true)
        XCTAssertTrue(viewModel.loadFailure?.error is DirectoryLoadTimeoutError)
        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertFalse(viewModel.isLoading)

        fileSystem.neverCompletes = false
        fileSystem.items = [recovered]
        viewModel.retryFailedDirectoryLoad()
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Recovered.txt"])
        XCTAssertNil(viewModel.loadFailure)
        XCTAssertFalse(viewModel.isLoading)

        fileSystem.completeTimedOutReads()
        await Task.yield()
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["Recovered.txt"])
        XCTAssertNil(viewModel.loadFailure)
    }

    func testDeallocationCancelsSuspendedLoadAndStopsDirectoryMonitoring() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let fileSystem = SuspendedFileSystem()
        let monitorFactory = PaneMonitorSourceFactory()
        let monitor = DirectoryMonitor(sourceFactory: monitorFactory)
        var viewModel: FilePaneViewModel? = FilePaneViewModel(
            initialDirectory: sandbox.allowedDirectory,
            fileSystem: fileSystem,
            accessPolicy: sandbox.policy,
            directoryMonitor: monitor
        )

        viewModel?.loadCurrentDirectory()
        await fileSystem.waitForRead()
        fileSystem.resume(items: [TestFileSystem.item(named: "Initial.txt", in: sandbox.allowedDirectory)])
        await waitUntilLoaded(try XCTUnwrap(viewModel))
        let source = try XCTUnwrap(monitorFactory.sources.first)

        viewModel?.loadCurrentDirectory(forceRefresh: true)
        await fileSystem.waitForRead()
        weak var weakViewModel = viewModel
        viewModel = nil

        XCTAssertNil(weakViewModel)
        XCTAssertTrue(source.wasCancelled)
        fileSystem.resume(items: [TestFileSystem.item(named: "Late.txt", in: sandbox.allowedDirectory)])
        await Task.yield()
        XCTAssertTrue(fileSystem.lastResumedReadObservedCancellation)
    }

    func testSuspendedLateCompletionCannotReplaceNewerPaneState() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let first = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/First")
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let fileSystem = SuspendedFileSystem()
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)

        viewModel.navigate(to: first)
        await fileSystem.waitForRead()
        viewModel.navigate(to: second)
        await fileSystem.waitForRead()
        fileSystem.resumeNewest(items: [TestFileSystem.item(named: "New.txt", in: second)])
        await waitUntilLoaded(viewModel)
        fileSystem.resume(items: [TestFileSystem.item(named: "Old.txt", in: first)])
        await Task.yield()

        XCTAssertEqual(viewModel.currentDirectory, second)
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), ["New.txt"])
    }

    func testSuccessfulBackAndForwardCommitHistoryWithLoadedDirectory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let fileSystem = TestFileSystem()
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)
        await load(viewModel)
        viewModel.navigate(to: second)
        await waitUntilLoaded(viewModel)

        viewModel.goBack()
        await waitUntilLoaded(viewModel)
        XCTAssertEqual(viewModel.currentDirectory, sandbox.allowedDirectory)
        XCTAssertEqual(viewModel.navigationHistory.current, sandbox.allowedDirectory)

        viewModel.goForward()
        await waitUntilLoaded(viewModel)
        XCTAssertEqual(viewModel.currentDirectory, second)
        XCTAssertEqual(viewModel.navigationHistory.current, second)
    }

    func testDeniedHistoryDestinationRetainsCompleteHistoryAndCurrentDirectory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        var readable = true
        let probe = SandboxFileAccessPolicy.AccessProbe(fileExists: { _ in readable }, isReadableFile: { _ in readable }, isWritableFile: { _ in true })
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: sandbox.root, accessProbe: probe)
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: TestFileSystem(), accessPolicy: policy)
        await load(viewModel)
        viewModel.navigate(to: second)
        await waitUntilLoaded(viewModel)
        let history = viewModel.navigationHistory
        readable = false

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentDirectory, second)
        XCTAssertEqual(viewModel.navigationHistory, history)
        XCTAssertEqual(viewModel.loadFailure?.directory, sandbox.allowedDirectory)
    }

    func testFailedHistoryReadRetainsCompleteHistory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let fileSystem = TestFileSystem()
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)
        await load(viewModel)
        viewModel.navigate(to: second)
        await waitUntilLoaded(viewModel)
        let history = viewModel.navigationHistory
        fileSystem.setError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError), for: sandbox.allowedDirectory)

        viewModel.goBack()
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, second)
        XCTAssertEqual(viewModel.navigationHistory, history)
    }

    func testTimedOutHistoryReadRetainsCompleteHistory() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let fileSystem = NeverCompletingFileSystem()
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy, directoryLoadTimeout: 0.01)
        await load(viewModel)
        viewModel.navigate(to: second)
        await waitUntilLoaded(viewModel)
        let history = viewModel.navigationHistory
        fileSystem.neverCompletes = true

        viewModel.goBack()
        await waitUntilLoaded(viewModel)

        XCTAssertEqual(viewModel.currentDirectory, second)
        XCTAssertEqual(viewModel.navigationHistory, history)
        XCTAssertTrue(viewModel.loadFailure?.isTimedOut == true)
    }

    func testSupersededHistoryLoadCannotCommitAfterNewerNavigation() async throws {
        let sandbox = try SandboxFixture(testCase: self)
        let second = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Second")
        let newest = try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Newest")
        let fileSystem = SuspendedFileSystem()
        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, fileSystem: fileSystem, accessPolicy: sandbox.policy)
        viewModel.navigate(to: second)
        await fileSystem.waitForRead()
        fileSystem.resume(items: [])
        await waitUntilLoaded(viewModel)

        viewModel.goBack()
        await fileSystem.waitForRead()
        viewModel.navigate(to: newest)
        await fileSystem.waitForRead()
        fileSystem.resumeNewest(items: [])
        await waitUntilLoaded(viewModel)
        fileSystem.resume(items: [])
        await Task.yield()

        XCTAssertEqual(viewModel.currentDirectory, newest)
        XCTAssertEqual(viewModel.navigationHistory.current, newest)
        XCTAssertEqual(viewModel.backDestination, second)
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

    private func waitUntilRequestCount(_ fileSystem: DelayedFileSystem, isAtLeast count: Int) async {
        while fileSystem.requestCount < count {
            await Task.yield()
        }
    }
}

private final class ScopeAssertingFileSystem: FileSystemServicing {
    private let isScopeActive: () -> Bool
    private(set) var allReadsHadActiveScope = true

    init(isScopeActive: @escaping () -> Bool) {
        self.isScopeActive = isScopeActive
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        allReadsHadActiveScope = allReadsHadActiveScope && isScopeActive()
        return DirectoryContentsResult(items: [], itemReadFailures: [])
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        allReadsHadActiveScope = allReadsHadActiveScope && isScopeActive()
        return DirectorySnapshotMetadata(resourceIdentifier: url.path, changeDate: .distantPast)
    }
}


private final class DelayedFileSystem: FileSystemServicing {
    private var responses: [URL: (items: [FileItem], error: Error?, delay: UInt64)] = [:]
    private(set) var requestCount = 0

    func setItems(_ items: [FileItem], for directory: URL, delay: UInt64) {
        responses[directory] = (items: items, error: nil, delay: delay)
    }

    func setError(_ error: Error, for directory: URL, delay: UInt64) {
        responses[directory] = (items: [], error: error, delay: delay)
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        requestCount += 1
        let response = responses[url] ?? (items: [], error: nil, delay: 0)
        if response.delay > 0 {
            try? await Task.sleep(nanoseconds: response.delay)
        }
        if let error = response.error {
            throw error
        }
        let visibleItems = includingHidden ? response.items : response.items.filter { !$0.isHidden }
        return DirectoryContentsResult(items: FileSystemService.sorted(visibleItems, descriptor: sort), itemReadFailures: [])
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        DirectorySnapshotMetadata(resourceIdentifier: url.path, changeDate: .distantPast)
    }
}

private final class NeverCompletingFileSystem: FileSystemServicing {
    var items: [FileItem] = []
    var neverCompletes = false
    private var pendingReadContinuations: [CheckedContinuation<Void, Never>] = []

    func completeTimedOutReads() {
        let continuations = pendingReadContinuations
        pendingReadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        if neverCompletes {
            await withCheckedContinuation { pendingReadContinuations.append($0) }
        }
        return DirectoryContentsResult(items: FileSystemService.sorted(items, descriptor: sort), itemReadFailures: [])
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        DirectorySnapshotMetadata(resourceIdentifier: url.path, changeDate: .distantPast)
    }
}

private final class SuspendedFileSystem: FileSystemServicing {
    private var continuations: [CheckedContinuation<[FileItem], Never>] = []
    private(set) var lastResumedReadObservedCancellation = false

    func waitForRead() async {
        while continuations.isEmpty {
            await Task.yield()
        }
    }

    func resume(items: [FileItem]) {
        guard !continuations.isEmpty else { return }
        let continuation = continuations.removeFirst()
        continuation.resume(returning: items)
    }

    func resumeNewest(items: [FileItem]) {
        guard let continuation = continuations.popLast() else { return }
        continuation.resume(returning: items)
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        let items = await withCheckedContinuation { continuations.append($0) }
        lastResumedReadObservedCancellation = Task.isCancelled
        return DirectoryContentsResult(items: FileSystemService.sorted(items, descriptor: sort), itemReadFailures: [])
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        DirectorySnapshotMetadata(resourceIdentifier: url.path, changeDate: .distantPast)
    }
}

private final class PaneMonitorSourceFactory: DirectoryMonitorSourceFactory {
    private(set) var sources: [PaneMonitorSource] = []

    func makeSource(for url: URL, queue: DispatchQueue) -> DirectoryMonitorSourceHandle? {
        let source = PaneMonitorSource()
        sources.append(source)
        return DirectoryMonitorSourceHandle(fileDescriptor: -1, source: source)
    }
}

private final class PaneMonitorSource: DirectoryMonitorSource {
    private(set) var wasCancelled = false
    func setEventHandler(_ handler: @escaping () -> Void) {}
    func setCancelHandler(_ handler: @escaping () -> Void) {}
    func resume() {}
    func cancel() { wasCancelled = true }
}

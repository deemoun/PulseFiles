import Foundation
import XCTest
@testable import PulseFiles

private struct FakeFolderAccessBookmarkResolver: FolderAccessBookmarkResolving {
    var stalePaths: Set<String> = []

    func makeBookmarkData(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return (url, stalePaths.contains(path))
    }
}

final class FolderAccessGrantServiceTests: XCTestCase {
    private var fixture: IsolatedDefaultsFixture!
    private var temporaryDirectory: TemporaryDirectoryFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try IsolatedDefaultsFixture(prefix: "FolderAccessGrantServiceTests", testCase: self)
        temporaryDirectory = try TemporaryDirectoryFixture(named: "FolderAccessGrantServiceTests", testCase: self)
    }

    override func tearDownWithError() throws {
        temporaryDirectory.cleanup()
        fixture.cleanup()
        temporaryDirectory = nil
        fixture = nil
        try super.tearDownWithError()
    }

    func testGrantPersistsBookmarkDataAndResolvesOnReload() throws {
        let grantedFolder = try temporaryDirectory.folder("Granted")
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())

        let grant = try service.grantAccess(to: grantedFolder)

        XCTAssertEqual(grant.url.path, grantedFolder.path)
        XCTAssertEqual(service.grants.count, 1)
        let reloaded = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        XCTAssertTrue(reloaded.hasGrant(containing: grantedFolder.appendingPathComponent("Nested/File.txt")))
        XCTAssertTrue(reloaded.staleGrantURLs.isEmpty)
    }

    func testStaleBookmarksAreDetectedForReauthorization() throws {
        let grantedFolder = try temporaryDirectory.folder("Stale")
        let resolver = AlwaysStaleFolderAccessBookmarkResolver()
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        try service.grantAccess(to: grantedFolder)

        let reloaded = FolderAccessGrantService(defaults: fixture.defaults, resolver: resolver)

        XCTAssertEqual(reloaded.staleGrantURLs.map(\.path), [grantedFolder.path])
        XCTAssertFalse(reloaded.hasGrant(containing: grantedFolder))
    }

    func testStaleBookmarksAreRewrittenWhenResolutionCanCreateFreshBookmark() throws {
        let grantedFolder = try temporaryDirectory.folder("RefreshableStale")
        let resolver = FakeFolderAccessBookmarkResolver(stalePaths: [grantedFolder.path])
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        try service.grantAccess(to: grantedFolder)

        let reloaded = FolderAccessGrantService(defaults: fixture.defaults, resolver: resolver)

        XCTAssertTrue(reloaded.staleGrantURLs.isEmpty)
        XCTAssertTrue(reloaded.hasGrant(containing: grantedFolder))
    }

    func testGrantAccessReusesExistingAncestorGrantForDescendant() throws {
        let parent = try temporaryDirectory.folder("Parent")
        let child = try temporaryDirectory.folder("Parent/Child")
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        let parentGrant = try service.grantAccess(to: parent)

        let childGrant = try service.grantAccess(to: child)

        XCTAssertEqual(childGrant.url.path, parentGrant.url.path)
        XCTAssertEqual(service.grants.map { $0.url.path }, [parent.path])
        XCTAssertTrue(service.hasGrant(containing: child.appendingPathComponent("Nested.txt")))
    }

    func testGrantStatusUsesAncestorGrantAndStopsScopedAccess() throws {
        let parent = try temporaryDirectory.folder("StatusParent")
        let child = try temporaryDirectory.folder("StatusParent/Child")
        var started: [URL] = []
        var stopped: [URL] = []
        let service = FolderAccessGrantService(
            defaults: fixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { started.append($0); return true },
            stopSecurityScopedAccess: { stopped.append($0) }
        )
        try service.grantAccess(to: parent)

        XCTAssertEqual(service.grantStatus(containing: child, canRead: { _ in true }), .available)
        XCTAssertEqual(started.map(\.path), [parent.path])
        XCTAssertEqual(stopped.map(\.path), [parent.path])
    }

    func testWithSecurityScopedAccessStopsAfterThrownBody() throws {
        let folder = try temporaryDirectory.folder("ThrowingScope")
        var events: [String] = []
        let service = FolderAccessGrantService(
            defaults: fixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in events.append("start"); return true },
            stopSecurityScopedAccess: { _ in events.append("stop") }
        )
        try service.grantAccess(to: folder)

        XCTAssertThrowsError(try service.withSecurityScopedAccess(to: [folder]) {
            XCTAssertEqual(events, ["start"])
            throw CocoaError(.fileReadNoPermission)
        })
        XCTAssertEqual(events, ["start", "stop"])
    }

    func testGrantStatusReportsStaleWhenMatchingBookmarkCannotResolve() throws {
        let folder = try temporaryDirectory.folder("Unresolvable")
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        service.grants = [FolderAccessGrant(url: folder, bookmarkData: Data("invalid".utf8))]
        let reloaded = FolderAccessGrantService(defaults: fixture.defaults, resolver: FailingFolderAccessBookmarkResolver())

        XCTAssertEqual(reloaded.grantStatus(containing: folder, canRead: { _ in true }), .staleOrUnavailable)
    }

    func testGrantStatusReportsResolvedGrantThatCannotProvideRequiredAccess() throws {
        let folder = try temporaryDirectory.folder("Inaccessible")
        var stops = 0
        let service = FolderAccessGrantService(
            defaults: fixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in true },
            stopSecurityScopedAccess: { _ in stops += 1 }
        )
        try service.grantAccess(to: folder)

        XCTAssertEqual(service.grantStatus(containing: folder, requireWritable: true, canRead: { _ in true }, canWrite: { _ in false }), .inaccessible)
        XCTAssertEqual(stops, 1)
    }

    func testGrantAccessCompactsDescendantGrantsWhenParentIsGranted() throws {
        let parent = try temporaryDirectory.folder("CompactParent")
        let child = try temporaryDirectory.folder("CompactParent/Child")
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        try service.grantAccess(to: child)

        try service.grantAccess(to: parent)

        XCTAssertEqual(service.grants.map { $0.url.path }, [parent.path])
        XCTAssertTrue(service.hasGrant(containing: child))
    }

    func testRemoveGrantDeletesPersistedAndResolvedCapability() throws {
        let grantedFolder = try temporaryDirectory.folder("Revocable")
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        try service.grantAccess(to: grantedFolder)

        XCTAssertTrue(service.removeGrant(for: grantedFolder))
        XCTAssertTrue(service.grants.isEmpty)
        XCTAssertFalse(service.hasGrant(containing: grantedFolder.appendingPathComponent("Nested")))
        XCTAssertFalse(service.removeGrant(for: grantedFolder))
    }

    func testRefreshResolvedGrantsUpdatesStaleGrantState() throws {
        let grantedFolder = try temporaryDirectory.folder("RefreshStale")
        let staleResolver = FakeFolderAccessBookmarkResolver(stalePaths: [grantedFolder.path])
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: staleResolver)
        service.grants = [FolderAccessGrant(url: grantedFolder, bookmarkData: Data(grantedFolder.path.utf8))]

        XCTAssertTrue(service.staleGrantURLs.isEmpty)
        service.refreshResolvedGrants()

        XCTAssertEqual(service.staleGrantURLs.map(\.path), [grantedFolder.path])
    }

    func testSettingsServiceExposesStoredFolderAccessGrants() throws {
        let grantedFolder = try temporaryDirectory.folder("SettingsGrant")
        let data = Data(grantedFolder.path.utf8)
        let settings = SettingsService(defaults: fixture.defaults)

        settings.folderAccessGrants = [FolderAccessGrant(url: grantedFolder, bookmarkData: data)]

        XCTAssertEqual(SettingsService(defaults: fixture.defaults).folderAccessGrants, [FolderAccessGrant(url: grantedFolder, bookmarkData: data)])
    }
}

private struct AlwaysStaleFolderAccessBookmarkResolver: FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }

    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path, isDirectory: true), true)
    }
}

private struct FailingFolderAccessBookmarkResolver: FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data { Data() }
    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        throw CocoaError(.fileReadCorruptFile)
    }
}

#if canImport(AppKit)
final class SettingsPermissionsCategoryTests: XCTestCase {
    func testPermissionsCategoryIsAvailableWithLockShieldSymbol() {
        XCTAssertTrue(SettingsViewController.Category.allCases.contains(.permissions))
        XCTAssertEqual(SettingsViewController.Category.permissions.symbolName, "lock.shield")
        XCTAssertEqual(SettingsViewController.Category.permissions.title, "Permissions".localized)
        XCTAssertEqual("Files & Folders Access".localized, "Files & Folders Access")
        XCTAssertEqual("Request Access".localized, "Request Access")
    }
}
#endif

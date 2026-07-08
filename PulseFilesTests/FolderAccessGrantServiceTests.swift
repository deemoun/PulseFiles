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
        let resolver = FakeFolderAccessBookmarkResolver(stalePaths: [grantedFolder.path])
        let service = FolderAccessGrantService(defaults: fixture.defaults, resolver: FakeFolderAccessBookmarkResolver())
        try service.grantAccess(to: grantedFolder)

        let reloaded = FolderAccessGrantService(defaults: fixture.defaults, resolver: resolver)

        XCTAssertEqual(reloaded.staleGrantURLs.map(\.path), [grantedFolder.path])
        XCTAssertTrue(reloaded.hasGrant(containing: grantedFolder))
    }

    func testSettingsServiceExposesStoredFolderAccessGrants() throws {
        let grantedFolder = try temporaryDirectory.folder("SettingsGrant")
        let data = Data(grantedFolder.path.utf8)
        let settings = SettingsService(defaults: fixture.defaults)

        settings.folderAccessGrants = [FolderAccessGrant(url: grantedFolder, bookmarkData: data)]

        XCTAssertEqual(SettingsService(defaults: fixture.defaults).folderAccessGrants, [FolderAccessGrant(url: grantedFolder, bookmarkData: data)])
    }
}

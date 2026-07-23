import XCTest
@testable import PulseFiles

final class SandboxFileAccessPolicyTests: XCTestCase {
    func testAppSandboxRootURLsAreAllowedWhenRestrictionIsEnabled() {
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: ExperimentalFlags.appSandboxRoot)
        let child = ExperimentalFlags.appSandboxRoot.appendingPathComponent("Nested/File.txt")

        XCTAssertTrue(policy.canAccess(ExperimentalFlags.appSandboxRoot))
        XCTAssertTrue(policy.canAccess(child))
        XCTAssertNoThrow(try policy.validateAccess(to: child))
    }

    func testURLsInsideFixtureSandboxRootAreAllowedWhenRestrictionIsEnabled() throws {
        let fixture = try SandboxFixture(testCase: self)
        let allowedFile = try fixture.allowedFile()

        XCTAssertTrue(fixture.policy.canAccess(fixture.root))
        XCTAssertTrue(fixture.policy.canAccess(fixture.allowedDirectory))
        XCTAssertTrue(fixture.policy.canAccess(allowedFile))
        XCTAssertNoThrow(try fixture.policy.validateAccess(to: allowedFile))
    }

    func testURLsOutsideSandboxRootAreRejected() throws {
        let fixture = try SandboxFixture(testCase: self)
        let externalFile = try fixture.externalFile()

        XCTAssertFalse(fixture.policy.canAccess(fixture.externalDirectory))
        XCTAssertFalse(fixture.policy.canAccess(externalFile))
        XCTAssertThrowsError(try fixture.policy.validateAccess(to: externalFile)) { error in
            guard case SandboxAccessError.outsideExperimentalSandbox(let rejectedURL) = error else {
                return XCTFail("Expected sandbox access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, externalFile)
        }
    }

    func testExplicitFolderGrantAllowsAccessOutsideSandboxRootWhenRestrictionIsEnabled() throws {
        let fixture = try SandboxFixture(testCase: self)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "SandboxFileAccessPolicyGrantTests", testCase: self)
        defer { defaultsFixture.cleanup() }
        let grantService = FolderAccessGrantService(
            defaults: defaultsFixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in true },
            stopSecurityScopedAccess: { _ in }
        )
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root, grantService: grantService)
        let externalFile = try fixture.externalFile("Granted/File.txt", contents: "granted")

        XCTAssertFalse(policy.canAccess(externalFile))

        try grantService.grantAccess(to: fixture.externalDirectory)

        XCTAssertTrue(policy.canAccess(externalFile))
        XCTAssertNoThrow(try policy.validateAccess(to: externalFile))
    }

    func testValidatedAccessKeepsGrantActiveForBodyAndStopsAfterError() throws {
        let fixture = try SandboxFixture(testCase: self)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "SandboxValidatedAccess", testCase: self)
        defer { defaultsFixture.cleanup() }
        var starts = 0
        var stops = 0
        let grants = FolderAccessGrantService(
            defaults: defaultsFixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in starts += 1; return true },
            stopSecurityScopedAccess: { _ in stops += 1 }
        )
        try grants.grantAccess(to: fixture.externalDirectory)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root, grantService: grants)

        XCTAssertThrowsError(try policy.withValidatedAccess(to: fixture.externalDirectory) {
            XCTAssertGreaterThanOrEqual(starts, 2) // validation then operation scope
            XCTAssertEqual(stops, starts - 1)
            throw CocoaError(.fileReadNoPermission)
        })
        XCTAssertEqual(starts, stops)
    }

    func testValidatedAsyncAccessStopsScopeAfterCancellation() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "SandboxValidatedAccessCancellation", testCase: self)
        defer { defaultsFixture.cleanup() }
        var activeScopes = 0
        let grants = FolderAccessGrantService(
            defaults: defaultsFixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in activeScopes += 1; return true },
            stopSecurityScopedAccess: { _ in activeScopes -= 1 }
        )
        try grants.grantAccess(to: fixture.externalDirectory)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root, grantService: grants)

        do {
            _ = try await policy.withValidatedAccess(to: fixture.externalDirectory) {
                XCTAssertGreaterThan(activeScopes, 0)
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(activeScopes, 0)
        }
    }

    func testResolvedGrantIsDeniedWhenInjectedProbeCannotReadIt() throws {
        let fixture = try SandboxFixture(testCase: self)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "SandboxFileAccessPolicyInaccessibleGrant", testCase: self)
        defer { defaultsFixture.cleanup() }
        let grantService = FolderAccessGrantService(
            defaults: defaultsFixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in true },
            stopSecurityScopedAccess: { _ in }
        )
        try grantService.grantAccess(to: fixture.externalDirectory)
        let policy = SandboxFileAccessPolicy(
            isEnabled: true,
            rootURL: fixture.root,
            grantService: grantService,
            accessProbe: .init(fileExists: { _ in true }, isReadableFile: { _ in false }, isWritableFile: { _ in false })
        )

        XCTAssertFalse(policy.canAccess(fixture.externalDirectory))
    }

    func testUnrelatedFolderSelectionDoesNotAuthorizeRequestedDirectory() throws {
        let fixture = try SandboxFixture(testCase: self)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "SandboxFileAccessPolicySelection", testCase: self)
        defer { defaultsFixture.cleanup() }
        let grantService = FolderAccessGrantService(
            defaults: defaultsFixture.defaults,
            resolver: FakeFolderAccessBookmarkResolver(),
            startSecurityScopedAccess: { _ in true },
            stopSecurityScopedAccess: { _ in }
        )
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root, grantService: grantService)
        let unrelated = try fixture.root.deletingLastPathComponent().appendingPathComponent("Unrelated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unrelated) }

        XCTAssertFalse(policy.grantSelectedFolder(unrelated, for: fixture.externalDirectory))
        XCTAssertFalse(policy.canAccess(fixture.externalDirectory))
    }

    func testSiblingPathsWithSimilarPrefixesAreRejected() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "PulseFilesSandboxPrefixTests", testCase: self)
        let root = try temporaryDirectory.folder("root")
        let sibling = try temporaryDirectory.folder("root-other")
        let siblingFile = try temporaryDirectory.file("root-other/escape.txt", contents: "outside")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)

        XCTAssertTrue(policy.canAccess(root.appendingPathComponent("child.txt")))
        XCTAssertFalse(policy.canAccess(sibling))
        XCTAssertFalse(policy.canAccess(siblingFile))
    }

    func testSymlinkTraversalCannotEscapeSandboxRoot() throws {
        let fixture = try SandboxFixture(testCase: self)
        let externalFile = try fixture.externalFile("Escaped.txt", contents: "outside")
        let link = fixture.allowedDirectory.appendingPathComponent("ExternalLink.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: externalFile)

        XCTAssertFalse(fixture.policy.canAccess(link))
        XCTAssertThrowsError(try fixture.policy.validateAccess(to: link)) { error in
            guard case SandboxAccessError.outsideExperimentalSandbox(let rejectedURL) = error else {
                return XCTFail("Expected sandbox access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, link)
        }
    }

    func testDisabledSandboxModeAllowsBroaderAccessOnlyThroughPolicy() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let externalFile = try fixture.externalFile(contents: "external")
        let unrestrictedService = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy)

        XCTAssertFalse(fixture.policy.canAccess(externalFile))
        XCTAssertThrowsError(try fixture.policy.validateAccess(to: externalFile))

        XCTAssertTrue(fixture.unrestrictedPolicy.canAccess(externalFile))
        XCTAssertNoThrow(try fixture.unrestrictedPolicy.validateAccess(to: externalFile))

        let result = try await unrestrictedService.copy(
            FileOperationRequest(sources: [externalFile], destinationDirectory: fixture.allowedDirectory),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: fixture.allowedDirectory.appendingPathComponent(externalFile.lastPathComponent)), "external")
    }

    func testSandboxEnabledAllowsOnlySandboxRootDescendants() throws {
        let fixture = try SandboxFixture(testCase: self)
        let descendant = fixture.root.appendingPathComponent("Nested/Allowed", isDirectory: true)
        let outside = fixture.externalDirectory

        XCTAssertTrue(fixture.policy.canAccess(fixture.root))
        XCTAssertTrue(fixture.policy.canAccess(descendant))
        XCTAssertFalse(fixture.policy.canAccess(outside))
    }

    func testSandboxDisabledDoesNotAutomaticallyAllowInaccessiblePaths() throws {
        let fixture = try SandboxFixture(testCase: self)
        let inaccessible = fixture.root
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertFalse(fixture.unrestrictedPolicy.canAccess(inaccessible))
        XCTAssertThrowsError(try fixture.unrestrictedPolicy.validateAccess(to: inaccessible)) { error in
            guard case SandboxAccessError.unauthorized(let rejectedURL) = error else {
                return XCTFail("Expected unauthorized access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, inaccessible)
        }
    }

    func testRejectedPathsPreserveAllowedFallbackDirectory() throws {
        let fixture = try SandboxFixture(testCase: self)
        let rejected = fixture.externalDirectory

        XCTAssertEqual(fixture.policy.validatedDirectory(rejected, fallback: fixture.allowedDirectory), fixture.allowedDirectory)
    }

    func testAlreadyReadableTemporaryDirectoriesRemainAccessibleWhenSandboxIsDisabled() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "PulseFilesReadableAccessTests", testCase: self)
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: ExperimentalFlags.appSandboxRoot)

        XCTAssertTrue(policy.canAccess(temporaryDirectory.root))
        XCTAssertNoThrow(try policy.validateAccess(to: temporaryDirectory.root))
        XCTAssertEqual(policy.validatedDirectory(temporaryDirectory.root), temporaryDirectory.root)
    }


    func testDisabledSandboxModeUsesInjectedProbeForSourceAccess() throws {
        let fixture = try SandboxFixture(testCase: self)
        let readableByDefault = try fixture.externalFile("ProbeDenied.txt", contents: "exists")
        let probe = SandboxFileAccessPolicy.AccessProbe(
            fileExists: { _ in true },
            isReadableFile: { _ in false },
            isWritableFile: { _ in true }
        )
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: fixture.root, accessProbe: probe)

        XCTAssertTrue(FileManager.default.isReadableFile(atPath: readableByDefault.path))
        XCTAssertFalse(policy.canAccess(readableByDefault))
        XCTAssertThrowsError(try policy.validateAccess(to: readableByDefault)) { error in
            guard case SandboxAccessError.unauthorized(let rejectedURL) = error else {
                return XCTFail("Expected unauthorized access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, readableByDefault)
        }
    }

    func testDisabledSandboxModeUsesInjectedProbeForDestinationAccess() throws {
        let fixture = try SandboxFixture(testCase: self)
        let destination = fixture.externalDirectory.appendingPathComponent("ProbeDestination.txt")
        let probe = SandboxFileAccessPolicy.AccessProbe(
            fileExists: { _ in true },
            isReadableFile: { _ in true },
            isWritableFile: { _ in false }
        )
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: fixture.root, accessProbe: probe)

        XCTAssertTrue(FileManager.default.isWritableFile(atPath: fixture.externalDirectory.path))
        XCTAssertThrowsError(try policy.validateDestinationAccess(to: destination)) { error in
            guard case SandboxAccessError.unauthorized(let rejectedURL) = error else {
                return XCTFail("Expected unauthorized destination error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, destination)
        }
    }

    func testDisabledSandboxModeCanAllowPathOnlyKnownToInjectedProbe() throws {
        let fixture = try SandboxFixture(testCase: self)
        let virtualURL = fixture.externalDirectory.appendingPathComponent("VirtualOnly")
        let probe = SandboxFileAccessPolicy.AccessProbe(
            fileExists: { $0 == virtualURL.standardizedFileURL.resolvingSymlinksInPath().path },
            isReadableFile: { $0 == virtualURL.standardizedFileURL.resolvingSymlinksInPath().path },
            isWritableFile: { _ in false }
        )
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: fixture.root, accessProbe: probe)

        XCTAssertFalse(FileManager.default.fileExists(atPath: virtualURL.path))
        XCTAssertTrue(policy.canAccess(virtualURL))
        XCTAssertNoThrow(try policy.validateAccess(to: virtualURL))
    }

    func testFileOperationPreflightRejectsSourceURLThatFailsPolicyValidation() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let outside = try fixture.externalFile("OutsideSource.txt", contents: "outside")
        let destination = fixture.allowedDirectory.appendingPathComponent(outside.lastPathComponent)

        await XCTAssertThrowsErrorAsync {
            try await fixture.fileOperationService().copy(
                FileOperationRequest(sources: [outside], destinationDirectory: fixture.allowedDirectory),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
        } errorHandler: { error in
            guard case SandboxAccessError.outsideExperimentalSandbox(let rejectedURL) = error else {
                return XCTFail("Expected sandbox access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, outside)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFileOperationPreflightRejectsDestinationURLThatFailsPolicyValidation() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let source = try fixture.allowedFile("AllowedSource.txt", contents: "inside")
        let destination = fixture.externalDirectory.appendingPathComponent(source.lastPathComponent)

        await XCTAssertThrowsErrorAsync {
            try await fixture.fileOperationService().copy(
                FileOperationRequest(sources: [source], destinationDirectory: fixture.externalDirectory),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
        } errorHandler: { error in
            guard case SandboxAccessError.outsideExperimentalSandbox(let rejectedURL) = error else {
                return XCTFail("Expected sandbox access error, got \(error)")
            }
            XCTAssertEqual(rejectedURL, fixture.externalDirectory)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

private struct FakeFolderAccessBookmarkResolver: FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path, isDirectory: true), false)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

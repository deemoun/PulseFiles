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

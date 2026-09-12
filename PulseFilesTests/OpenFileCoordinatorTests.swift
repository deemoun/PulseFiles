// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class OpenFileCoordinatorTests: XCTestCase {
    func testAllowedApplicationIsValidatedAndHandedOff() async throws {
        let temporary = try TemporaryDirectoryFixture(named: "OpenFileAllowed", testCase: self)
        let file = try temporary.file("Root/Document.txt", contents: "document")
        let application = try temporary.folder("Root/Editor.app")
        var request: (URL, URL?)?
        let coordinator = OpenFileCoordinator(
            accessPolicy: .init(isEnabled: true, rootURL: temporary.root.appendingPathComponent("Root")),
            probe: OpenFileProbe(applicationBundle: { $0 == application }),
            handoff: { request = ($0, $1) }
        )

        try await coordinator.open(file, with: application)

        XCTAssertEqual(request?.0, file)
        XCTAssertEqual(request?.1, application)
    }

    func testMissingApplicationIsRejectedBeforeHandoff() async throws {
        let temporary = try TemporaryDirectoryFixture(named: "OpenFileMissingApplication", testCase: self)
        let root = try temporary.folder("Root")
        let file = try temporary.file("Root/Document.txt", contents: "document")
        let application = root.appendingPathComponent("Missing.app", isDirectory: true)
        var didHandoff = false
        let coordinator = OpenFileCoordinator(
            accessPolicy: .init(isEnabled: true, rootURL: root),
            probe: OpenFileProbe(applicationBundle: { _ in true }),
            handoff: { _, _ in didHandoff = true }
        )

        do { try await coordinator.open(file, with: application); XCTFail("Expected missing application") } catch { XCTAssertEqual(error as? FileOperationError, .sourceMissing(application)) }
        XCTAssertFalse(didHandoff)
    }

    func testExistingNonApplicationIsRejectedBeforeHandoff() async throws {
        let temporary = try TemporaryDirectoryFixture(named: "OpenFileInvalidApplication", testCase: self)
        let root = try temporary.folder("Root")
        let file = try temporary.file("Root/Document.txt", contents: "document")
        let application = try temporary.folder("Root/NotAnApplication")
        var didHandoff = false
        let coordinator = OpenFileCoordinator(
            accessPolicy: .init(isEnabled: true, rootURL: root),
            probe: OpenFileProbe(applicationBundle: { _ in false }),
            handoff: { _, _ in didHandoff = true }
        )

        do { try await coordinator.open(file, with: application); XCTFail("Expected invalid application") } catch { XCTAssertEqual(error as? OpenFileValidationError, .notApplicationBundle(application)) }
        XCTAssertFalse(didHandoff)
    }

    func testDeniedApplicationURLSurfacesPolicyErrorBeforeHandoff() async throws {
        let temporary = try TemporaryDirectoryFixture(named: "OpenFileDeniedApplication", testCase: self)
        let root = try temporary.folder("Root")
        let file = try temporary.file("Root/Document.txt", contents: "document")
        let application = try temporary.folder("Outside/Editor.app")
        var didHandoff = false
        let coordinator = OpenFileCoordinator(
            accessPolicy: .init(isEnabled: true, rootURL: root),
            probe: OpenFileProbe(applicationBundle: { _ in true }),
            handoff: { _, _ in didHandoff = true }
        )

        do { try await coordinator.open(file, with: application); XCTFail("Expected denied application") } catch { XCTAssertEqual(error as? SandboxAccessError, .outsideExperimentalSandbox(application)) }
        XCTAssertFalse(didHandoff)
    }

    func testBothExplicitlyGrantedURLsRemainScopedThroughHandoff() async throws {
        let temporary = try TemporaryDirectoryFixture(named: "OpenFileGrantedURLs", testCase: self)
        let defaults = try IsolatedDefaultsFixture(prefix: "OpenFileGrantedURLs", testCase: self)
        defer { defaults.cleanup() }
        let fileFolder = try temporary.folder("Files")
        let applicationFolder = try temporary.folder("Applications")
        let file = try temporary.file("Files/Document.txt", contents: "document")
        let application = try temporary.folder("Applications/Editor.app")
        var activeScopes = 0
        let grants = FolderAccessGrantService(
            defaults: defaults.defaults,
            resolver: OpenFileBookmarkResolver(),
            startSecurityScopedAccess: { _ in activeScopes += 1; return true },
            stopSecurityScopedAccess: { _ in activeScopes -= 1 }
        )
        try grants.grantAccess(to: fileFolder)
        try grants.grantAccess(to: applicationFolder)
        let inaccessibleRoot = temporary.root.appendingPathComponent("SandboxRoot", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: inaccessibleRoot, grantService: grants)
        var scopesDuringHandoff = 0
        let coordinator = OpenFileCoordinator(
            accessPolicy: policy,
            probe: OpenFileProbe(applicationBundle: { $0 == application }),
            handoff: { _, _ in scopesDuringHandoff = activeScopes }
        )

        try await coordinator.open(file, with: application)

        XCTAssertEqual(scopesDuringHandoff, 2)
        XCTAssertEqual(activeScopes, 0)
    }
}

private struct OpenFileBookmarkResolver: FolderAccessBookmarkResolving {
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

private struct OpenFileProbe: FileSystemProbing {
    let applicationBundle: @Sendable (URL) -> Bool
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { .value(FileManager.default.fileExists(atPath: url.path)) }
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { .unavailable }
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?> { .unavailable }
    func isApplicationBundle(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { .value(applicationBundle(url)) }
}

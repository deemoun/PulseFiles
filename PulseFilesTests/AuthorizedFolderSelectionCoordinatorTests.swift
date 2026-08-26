// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

@MainActor
final class AuthorizedFolderSelectionCoordinatorTests: XCTestCase {
    private final class Resolver: FolderAccessBookmarkResolving {
        var makeCount = 0
        var makeError: Error?

        func makeBookmarkData(for url: URL) throws -> Data {
            makeCount += 1
            if let makeError { throw makeError }
            return Data(url.path.utf8)
        }

        func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
            (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false)
        }
    }

    private struct Fixture {
        let root: URL
        let external: URL
        let defaults: UserDefaults
        let suiteName: String
        let resolver: Resolver
        let grants: FolderAccessGrantService
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let resolver = Resolver()
        let grants = FolderAccessGrantService(
            defaults: defaults,
            resolver: resolver,
            startSecurityScopedAccess: { _ in true },
            stopSecurityScopedAccess: { _ in }
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
            defaults.removePersistentDomain(forName: suiteName)
        }
        return Fixture(root: root, external: external, defaults: defaults, suiteName: suiteName, resolver: resolver, grants: grants)
    }

    private func policy(_ fixture: Fixture, grants: FolderAccessGrantService? = nil) -> SandboxFileAccessPolicy {
        SandboxFileAccessPolicy(
            isEnabled: true,
            rootURL: fixture.root,
            grantService: grants ?? fixture.grants,
            accessProbe: .init(fileExists: { _ in true }, isReadableFile: { _ in true }, isWritableFile: { _ in true })
        )
    }

    func testAlreadyAuthorizedURLDoesNotCreateGrant() throws {
        let fixture = try fixture()
        let coordinator = AuthorizedFolderSelectionCoordinator(accessPolicy: policy(fixture), grantService: fixture.grants)
        let result = coordinator.resolve(selectedURL: fixture.root.appendingPathComponent("."), for: .init(prompt: "Choose"))

        XCTAssertEqual(try result.get(), fixture.root.standardizedFileURL)
        XCTAssertEqual(fixture.resolver.makeCount, 0)
    }

    func testNewlyGrantedURLIsValidatedAndReturned() throws {
        let fixture = try fixture()
        let coordinator = AuthorizedFolderSelectionCoordinator(accessPolicy: policy(fixture), grantService: fixture.grants)

        XCTAssertEqual(try coordinator.resolve(selectedURL: fixture.external, for: .init(prompt: "Choose")).get(), fixture.external)
        XCTAssertEqual(fixture.resolver.makeCount, 1)
    }

    func testDeniedGrantReturnsTypedGrantFailure() throws {
        let fixture = try fixture()
        fixture.resolver.makeError = CocoaError(.fileReadNoPermission)
        let coordinator = AuthorizedFolderSelectionCoordinator(accessPolicy: policy(fixture), grantService: fixture.grants)

        guard case .failure(.grant) = coordinator.resolve(selectedURL: fixture.external, for: .init(prompt: "Choose")) else {
            return XCTFail("Expected grant failure")
        }
    }

    func testExperimentalRootRestrictionRequiresGrantForExternalURL() throws {
        let fixture = try fixture()
        let coordinator = AuthorizedFolderSelectionCoordinator(accessPolicy: policy(fixture), grantService: fixture.grants)

        _ = coordinator.resolve(selectedURL: fixture.external, for: .init(prompt: "Choose"))
        XCTAssertEqual(fixture.resolver.makeCount, 1)
    }

    func testPolicyRejectionAfterGrantResolutionReturnsTypedFailure() throws {
        let fixture = try fixture()
        let otherGrants = FolderAccessGrantService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = AuthorizedFolderSelectionCoordinator(accessPolicy: policy(fixture, grants: otherGrants), grantService: fixture.grants)

        guard case .failure(.rejected(let error)) = coordinator.resolve(selectedURL: fixture.external, for: .init(prompt: "Choose")) else {
            return XCTFail("Expected post-grant policy rejection")
        }
        XCTAssertTrue(error is SandboxAccessError)
    }
}

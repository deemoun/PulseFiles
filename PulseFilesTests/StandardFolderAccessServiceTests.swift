// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class StandardFolderAccessServiceTests: XCTestCase {
    func testResolvesStandardFolderWithFileManagerSearchPathDirectory() {
        let expected = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        var requestedDirectory: FileManager.SearchPathDirectory?
        let service = StandardFolderAccessService(
            accessPolicy: SandboxFileAccessPolicy(isEnabled: false, rootURL: expected),
            urlResolver: { directory in requestedDirectory = directory; return expected },
            directoryReader: { _ in }
        )

        XCTAssertEqual(service.url(for: .documents), expected.standardizedFileURL)
        XCTAssertEqual(requestedDirectory, .documentDirectory)
    }

    func testExperimentalSandboxBlocksStandardFolderReadBeforeItIsAttempted() {
        let root = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
        var readAttempted = false
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
        let service = StandardFolderAccessService(
            accessPolicy: policy,
            urlResolver: { _ in desktop },
            directoryReader: { _ in readAttempted = true }
        )

        XCTAssertEqual(service.requestAccess(for: .desktop), .blockedByExperimentalSandbox)
        XCTAssertFalse(readAttempted)
    }

    func testPermissionErrorsRequireSystemSettingsReview() {
        XCTAssertEqual(StandardFolderAccessService.state(for: CocoaError(.fileReadNoPermission)), .requiresSystemSettingsReview)
        XCTAssertEqual(StandardFolderAccessService.state(for: POSIXError(.EACCES)), .requiresSystemSettingsReview)
    }

    func testSuccessfulMinimalReadReportsAccessibleAndOtherFailuresAreUnavailable() {
        let folder = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: folder)
        let success = StandardFolderAccessService(accessPolicy: policy, urlResolver: { _ in folder }, directoryReader: { _ in })
        let unavailable = StandardFolderAccessService(accessPolicy: policy, urlResolver: { _ in folder }, directoryReader: { _ in throw CocoaError(.fileNoSuchFile) })

        XCTAssertEqual(success.requestAccess(for: .downloads), .accessible)
        XCTAssertEqual(unavailable.requestAccess(for: .downloads), .deniedOrUnavailable)
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class CompositionRootUITests: XCTestCase {
    func testNestedControllersRetainDependenciesBuiltFromTheWindowSharedPolicy() {
        let deniedRoot = URL(fileURLWithPath: "/composition-denied", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: deniedRoot)
        let fileSystem = CompositionFileSystemSpy()
        let grants = CompositionGrantSpy()
        let directorySizing = CompositionDirectorySizingSpy(accessPolicy: policy)
        let base = MainWindowDependencies.production(accessPolicy: policy)
        let dependencies = base.replacingPaneComposition(
            accessPolicy: policy,
            paneFileSystem: fileSystem,
            folderAccessGrants: grants,
            directorySizing: directorySizing
        )
        let controller = MainWindowViewController(
            settings: SettingsService(accessPolicy: policy),
            dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy),
            sandboxRootEnsurer: {}
        )

        controller.loadViewIfNeeded()
        let composition = controller.compositionForTesting

        XCTAssertTrue(composition.paneFileSystems.allSatisfy { $0 === fileSystem })
        XCTAssertTrue(composition.panePolicies.allSatisfy { $0 === policy })
        XCTAssertTrue(composition.sidebarPolicy === policy)
        XCTAssertTrue(composition.sidebarDirectorySizing === directorySizing)
        XCTAssertTrue(directorySizing.accessPolicy === policy)
        XCTAssertTrue(composition.terminalPolicy === policy)
        XCTAssertTrue(composition.folderAccessGrants === grants)
    }

    func testStartingTerminalSessionUsesInjectedProcessFactory() {
        let policy = SandboxFileAccessPolicy.current
        let process = CompositionTerminalProcessSpy()
        var factoryInvocationCount = 0
        let dependencies = MainWindowDependencies.production(accessPolicy: policy)
            .replacingTerminalProcessFactory {
                factoryInvocationCount += 1
                return process
            }
        let settings = SettingsService(accessPolicy: policy)
        settings.experimentalTerminalEnabled = true
        settings.hasAcknowledgedTerminalWarning = true
        let controller = MainWindowViewController(
            settings: settings,
            dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy),
            sandboxRootEnsurer: {}
        )

        controller.loadViewIfNeeded()
        controller.startTerminalSessionForCompositionTesting()

        XCTAssertEqual(factoryInvocationCount, 1)
        XCTAssertTrue(process.didRun)
    }
}

private final class CompositionDirectorySizingSpy: DirectorySizing, @unchecked Sendable {
    let accessPolicy: SandboxFileAccessPolicy

    init(accessPolicy: SandboxFileAccessPolicy) {
        self.accessPolicy = accessPolicy
    }

    func size(of root: URL) async throws -> DirectorySizeResult {
        DirectorySizeResult(bytes: 0, completeness: .complete)
    }
}

private final class CompositionFileSystemSpy: FileSystemServicing {
    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        DirectoryContentsResult(items: [], itemReadFailures: [])
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        DirectorySnapshotMetadata(resourceIdentifier: nil, changeDate: nil)
    }
}

private final class CompositionGrantSpy: FolderAccessGrantProviding {
    func grantAccess(to directory: URL) throws -> FolderAccessGrant {
        FolderAccessGrant(url: directory, bookmarkData: Data())
    }
}

private final class CompositionTerminalProcessSpy: TerminalProcess {
    var isRunning = true
    var terminationStatus: Int32 = 0
    var outputHandler: ((Data) -> Void)?
    var terminationHandler: ((TerminalProcess) -> Void)?
    private(set) var didRun = false

    func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL) {}
    func run() throws { didRun = true }
    func write(_ data: Data) {}
    func resize(columns: Int, rows: Int) {}
    func terminate() { isRunning = false }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles
@testable import PulseFilesTerminal

@MainActor
final class CompositionRootUITests: XCTestCase {
    func testTerminalFocusKeepsEditingKeysOutOfPaneCommandRouting() throws {
        let suiteName = "TerminalKeys-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = SandboxFileAccessPolicy.current
        let settings = SettingsService.testing(defaults: defaults, accessPolicy: policy)
        settings.experimentalTerminalEnabled = true
        settings.hasAcknowledgedTerminalWarning = true
        let dependencies = MainWindowDependencies.production(accessPolicy: policy, folderAccessGrants: FolderAccessGrantService.shared)
            .replacingTerminalProcessFactory { CompositionTerminalProcessSpy() }
        let controller = MainWindowViewController(settings: settings, dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy), sandboxRootEnsurer: {})
        let window = NSWindow(contentViewController: controller)
        defer { window.contentViewController = nil }
        controller.menuToggleTerminal(nil)
        func surface(in view: NSView) -> TerminalTextView? {
            if let terminal = view as? TerminalTextView { return terminal }
            return view.subviews.compactMap { surface(in: $0) }.first
        }
        let terminal = try XCTUnwrap(surface(in: controller.view))
        XCTAssertTrue(window.makeFirstResponder(terminal))
        for code: UInt16 in [51, 123, 124, 125, 126, 36, 48, 53] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            XCTAssertFalse(controller.handleGlobalKeyDown(event), "Pane routing consumed terminal key \(code)")
            XCTAssertTrue(window.firstResponder === terminal)
        }
        controller.menuToggleTerminal(nil)
    }

    func testNestedControllersRetainDependenciesBuiltFromTheWindowSharedPolicy() {
        let deniedRoot = URL(fileURLWithPath: "/composition-denied", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: deniedRoot)
        let fileSystem = CompositionFileSystemSpy()
        let grants = CompositionGrantSpy()
        let directorySizing = CompositionDirectorySizingSpy(accessPolicy: policy)
        let base = MainWindowDependencies.production(accessPolicy: policy, folderAccessGrants: FolderAccessGrantService.shared)
        let dependencies = base.replacingPaneComposition(
            accessPolicy: policy,
            paneFileSystem: fileSystem,
            folderAccessGrants: grants,
            directorySizing: directorySizing
        )
        let controller = MainWindowViewController(
            settings: SettingsService.testing(defaults: .standard, accessPolicy: policy),
            dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy),
            sandboxRootEnsurer: {}
        )

        controller.loadViewIfNeeded()
        let composition = controller.compositionForTesting

        XCTAssertTrue(composition.paneFileSystems.allSatisfy { $0 === fileSystem })
        XCTAssertTrue(composition.panePolicyIdentities.allSatisfy { $0 == ObjectIdentifier(policy) })
        XCTAssertTrue(composition.sidebarPolicyIdentity == ObjectIdentifier(policy))
        XCTAssertTrue(composition.sidebarDirectorySizing === directorySizing)
        XCTAssertTrue(directorySizing.accessPolicy === policy)
        XCTAssertTrue(composition.terminalPolicyIdentity == ObjectIdentifier(policy))
        XCTAssertTrue(composition.folderAccessGrants === grants)
    }

    func testDefaultVisibleEnabledTerminalStartsAutomaticallyAfterCallbacksAreBound() throws {
        let suiteName = "TerminalStartup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = SandboxFileAccessPolicy.current
        let process = CompositionTerminalProcessSpy()
        var starts = 0
        let dependencies = MainWindowDependencies.production(accessPolicy: policy, folderAccessGrants: FolderAccessGrantService.shared)
            .replacingTerminalProcessFactory { starts += 1; return process }
        let settings = SettingsService.testing(defaults: defaults, accessPolicy: policy)
        settings.experimentalTerminalEnabled = true
        settings.defaultTerminalVisible = true
        settings.hasAcknowledgedTerminalWarning = true
        let controller = MainWindowViewController(settings: settings, dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy), sandboxRootEnsurer: {})
        controller.loadViewIfNeeded()
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(process.didRun)
        controller.startTerminalSessionForCompositionTesting()
        XCTAssertEqual(starts, 1)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        for size in [NSSize(width: 1200, height: 800), NSSize(width: 1000, height: 650), NSSize(width: 1400, height: 900)] {
            window.setContentSize(size)
            controller.view.layoutSubtreeIfNeeded()
            controller.view.displayIfNeeded()
        }
    }

    func testStartingTerminalSessionUsesInjectedProcessFactory() {
        let policy = SandboxFileAccessPolicy.current
        let process = CompositionTerminalProcessSpy()
        var factoryInvocationCount = 0
        let dependencies = MainWindowDependencies.production(accessPolicy: policy, folderAccessGrants: FolderAccessGrantService.shared)
            .replacingTerminalProcessFactory {
                factoryInvocationCount += 1
                return process
            }
        let settings = SettingsService.testing(defaults: .standard, accessPolicy: policy)
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

    func testOpeningRealTerminalAtRootDoesNotCrashWindowLayout() throws {
        let suiteName = "TerminalLayout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: URL(fileURLWithPath: "/"))
        let settings = SettingsService.testing(defaults: defaults, accessPolicy: policy)
        settings.experimentalTerminalEnabled = true
        settings.hasAcknowledgedTerminalWarning = true
        settings.defaultSidebarVisible = false
        settings.liquidGlassEnabled = true
        settings.startupLeftDirectory = URL(fileURLWithPath: "/", isDirectory: true)
        settings.rightPanePresentationMode = .brief
        let dependencies = MainWindowDependencies.production(accessPolicy: policy, folderAccessGrants: FolderAccessGrantService.shared)
        let controller = MainWindowViewController(settings: settings, dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: policy), sandboxRootEnsurer: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.contentViewController = nil }
        for index in 0..<10 {
            controller.menuToggleTerminal(nil)
            window.setContentSize(NSSize(width: index.isMultiple(of: 2) ? 1100 : 1200, height: 750))
            controller.view.layoutSubtreeIfNeeded()
            controller.view.displayIfNeeded()
        }
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

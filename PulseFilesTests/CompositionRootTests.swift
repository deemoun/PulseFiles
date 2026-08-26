// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class CompositionRootTests: XCTestCase {
    func testPaneCompositionReplacementUsesOneInjectedGrantCapability() {
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: URL(fileURLWithPath: "/sandbox"))
        let grants = CompositionRootGrantSpy()
        let base = MainWindowDependencies.production(accessPolicy: policy)
        let replaced = base.replacingPaneComposition(
            accessPolicy: policy,
            paneFileSystem: CompositionRootFileSystemSpy(),
            folderAccessGrants: grants,
            directorySizing: CompositionRootDirectorySizingSpy()
        )

        XCTAssertTrue(replaced.folderAccessGrants === grants)
        XCTAssertTrue(replaced.authorizedFolderSelection.grantServiceForCompositionTesting === grants)
    }

    func testStartupConfigurationAndWindowFactoryShareInjectedSettings() throws {
        let fixture = try IsolatedDefaultsFixture(prefix: "CompositionRootTests", testCase: self)
        let settings = SettingsService(defaults: fixture.defaults)
        settings.appLanguage = .russian
        settings.fileColorScheme = .minimal

        var windowSettings: SettingsService?
        var windowController: MainWindowController?
        let delegate = AppDelegate(
            launchArguments: ["PulseFiles"],
            userDefaults: fixture.defaults,
            settings: settings
        ) { suppliedSettings in
            windowSettings = suppliedSettings
            let controller = AppDelegate.makeProductionMainWindowController(
                settings: suppliedSettings,
                sandboxRootEnsurer: {}
            )
            windowController = controller
            return controller
        }
        defer {
            windowController?.close()
            LocalizationConfiguration.configure(language: .english)
            FileTypeColorPalette.activeScheme = .default
        }

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertTrue(windowSettings === settings)
        XCTAssertEqual(LocalizationConfiguration.language, .russian)
        XCTAssertEqual(
            FileTypeColorPalette.folder.usingColorSpace(.deviceRGB),
            settings.fileColorScheme.color(for: .folder).usingColorSpace(.deviceRGB)
        )
    }
}

private final class CompositionRootGrantSpy: FolderAccessGrantProviding {
    func grantAccess(to directory: URL) throws -> FolderAccessGrant {
        FolderAccessGrant(url: directory, bookmarkData: Data())
    }
}

private final class CompositionRootFileSystemSpy: FileSystemServicing {
    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        DirectoryContentsResult(items: [], itemReadFailures: [])
    }
    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        DirectorySnapshotMetadata(resourceIdentifier: nil, changeDate: nil)
    }
}

private struct CompositionRootDirectorySizingSpy: DirectorySizing {
    func size(of root: URL) async throws -> DirectorySizeResult {
        DirectorySizeResult(bytes: 0, completeness: .complete)
    }
}

import AppKit
import XCTest
@testable import PulseFiles

final class SettingsServiceTests: XCTestCase {
    private var fixture: IsolatedDefaultsFixture!
    private var settings: SettingsService!
    private var settingsJSONFixture: TemporaryDirectoryFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try IsolatedDefaultsFixture(prefix: "SettingsServiceTests", testCase: self)
        settingsJSONFixture = try TemporaryDirectoryFixture(named: "SettingsServiceJSONTests", testCase: self)
        settings = makeSettings()
    }

    override func tearDownWithError() throws {
        fixture.cleanup()
        settings = nil
        settingsJSONFixture = nil
        fixture = nil
        try super.tearDownWithError()
    }

    func testDirectorySettingsDefaultAndRoundTrip() throws {
        XCTAssertEqual(settings.lastLeftDirectory, FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertEqual(settings.lastRightDirectory, FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertNil(settings.startupLeftDirectory)
        XCTAssertNil(settings.startupRightDirectory)
        XCTAssertEqual(settings.launchLeftDirectory, settings.lastLeftDirectory)
        XCTAssertEqual(settings.launchRightDirectory, settings.lastRightDirectory)

        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceDirectoryTests", testCase: self)
        let lastLeft = try temporaryDirectory.folder("Projects")
        let lastRight = try temporaryDirectory.folder("Downloads")
        let startupLeft = try temporaryDirectory.folder("Startup Left")
        let startupRight = try temporaryDirectory.folder("Startup Right")

        settings.lastLeftDirectory = lastLeft
        settings.lastRightDirectory = lastRight
        settings.startupLeftDirectory = startupLeft
        settings.startupRightDirectory = startupRight

        let reloaded = makeSettings()
        XCTAssertEqual(reloaded.lastLeftDirectory, lastLeft)
        XCTAssertEqual(reloaded.lastRightDirectory, lastRight)
        XCTAssertEqual(reloaded.startupLeftDirectory, startupLeft)
        XCTAssertEqual(reloaded.startupRightDirectory, startupRight)
        XCTAssertEqual(reloaded.launchLeftDirectory, startupLeft)
        XCTAssertEqual(reloaded.launchRightDirectory, startupRight)

        reloaded.startupLeftDirectory = nil
        reloaded.startupRightDirectory = nil
        XCTAssertNil(makeSettings().startupLeftDirectory)
        XCTAssertNil(makeSettings().startupRightDirectory)
    }


    func testNormalDefaultsFallBackToHomeWhenPreferredDirectoryIsNotAccessible() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceHomeFallbackTests", testCase: self)
        let accessibleHome = try temporaryDirectory.folder("Home")
        let inaccessibleDocuments = temporaryDirectory.path("MissingDocuments", isDirectory: true)
        let appSupport = try temporaryDirectory.folder("Application Support/PulseFiles")
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: ExperimentalFlags.appSandboxRoot)
        let fallbackSettings = SettingsService(
            defaults: fixture.defaults,
            accessPolicy: policy,
            homeDirectoryProvider: { accessibleHome },
            documentsDirectoryProvider: { inaccessibleDocuments },
            applicationSupportDirectoryProvider: { appSupport }
        )

        XCTAssertEqual(fallbackSettings.lastLeftDirectory, accessibleHome)
        XCTAssertEqual(fallbackSettings.lastRightDirectory, accessibleHome)
    }

    func testFreshInstallUsesHomeForBothPanesWithoutCheckingDownloads() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceFreshInstallTests", testCase: self)
        let home = try temporaryDirectory.folder("Home")
        let protectedDownloads = temporaryDirectory.path("Downloads", isDirectory: true)
        var checkedPaths: [String] = []
        let policy = SandboxFileAccessPolicy(
            isEnabled: false,
            rootURL: home,
            accessProbe: .init(
                fileExists: { path in checkedPaths.append(path); return path == home.path },
                isReadableFile: { path in checkedPaths.append(path); return path == home.path },
                isWritableFile: { _ in true }
            )
        )
        let freshSettings = SettingsService(
            defaults: fixture.defaults,
            accessPolicy: policy,
            homeDirectoryProvider: { home },
            applicationSupportDirectoryProvider: { home }
        )

        XCTAssertEqual(freshSettings.startupDirectoryResolution(for: .left).directory, home)
        XCTAssertEqual(freshSettings.startupDirectoryResolution(for: .right).directory, home)
        XCTAssertFalse(checkedPaths.contains(protectedDownloads.path))
    }

    func testInaccessibleUserSelectedStartupFolderFallsBackAndPreservesPreference() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceStartupRecoveryTests", testCase: self)
        let home = try temporaryDirectory.folder("Home")
        let protectedFolder = temporaryDirectory.path("Protected", isDirectory: true)
        let policy = SandboxFileAccessPolicy(
            isEnabled: false,
            rootURL: home,
            accessProbe: .init(fileExists: { $0 == home.path }, isReadableFile: { $0 == home.path }, isWritableFile: { _ in true })
        )
        let recoveredSettings = SettingsService(defaults: fixture.defaults, accessPolicy: policy, homeDirectoryProvider: { home }, applicationSupportDirectoryProvider: { home })
        recoveredSettings.startupRightDirectory = protectedFolder

        let resolution = recoveredSettings.startupDirectoryResolution(for: .right)
        XCTAssertEqual(resolution.directory, home)
        XCTAssertEqual(resolution.requestedDirectory, protectedFolder)
        XCTAssertEqual(resolution.source, .userSelected)
        XCTAssertTrue(resolution.needsAccessRecovery)
        XCTAssertEqual(recoveredSettings.startupRightDirectory, protectedFolder)
    }

    func testAccessibleUserSelectedStartupFolderReopensWithoutRecovery() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceGrantedStartupTests", testCase: self)
        let home = try temporaryDirectory.folder("Home")
        let grantedFolder = try temporaryDirectory.folder("Granted")
        let policy = SandboxFileAccessPolicy(
            isEnabled: false,
            rootURL: home,
            accessProbe: .init(fileExists: { $0 == home.path || $0 == grantedFolder.path }, isReadableFile: { $0 == home.path || $0 == grantedFolder.path }, isWritableFile: { _ in true })
        )
        let grantedSettings = SettingsService(defaults: fixture.defaults, accessPolicy: policy, homeDirectoryProvider: { home }, applicationSupportDirectoryProvider: { home })
        grantedSettings.startupLeftDirectory = grantedFolder

        let resolution = grantedSettings.startupDirectoryResolution(for: .left)
        XCTAssertEqual(resolution.directory, grantedFolder)
        XCTAssertFalse(resolution.needsAccessRecovery)
    }

    func testNormalDefaultsFallBackToApplicationSupportWhenPreferredAndHomeAreNotAccessible() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture(named: "SettingsServiceApplicationSupportFallbackTests", testCase: self)
        let inaccessibleHome = temporaryDirectory.path("MissingHome", isDirectory: true)
        let inaccessibleDocuments = temporaryDirectory.path("MissingDocuments", isDirectory: true)
        let appSupport = temporaryDirectory.path("Application Support/PulseFiles", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: ExperimentalFlags.appSandboxRoot)
        let fallbackSettings = SettingsService(
            defaults: fixture.defaults,
            accessPolicy: policy,
            homeDirectoryProvider: { inaccessibleHome },
            documentsDirectoryProvider: { inaccessibleDocuments },
            applicationSupportDirectoryProvider: { appSupport }
        )

        XCTAssertEqual(fallbackSettings.lastLeftDirectory, appSupport)
        XCTAssertEqual(fallbackSettings.lastRightDirectory, appSupport)
    }

    func testExperimentalSandboxDefaultsUseSandboxPaneDirectoriesOnlyWhenEnabled() {
        settings.experimentalSandboxEnabled = true

        let sandboxedSettings = makeSettings()

        #if DEBUG
        XCTAssertEqual(sandboxedSettings.lastLeftDirectory, ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true))
        XCTAssertEqual(sandboxedSettings.lastRightDirectory, ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true))
        #else
        XCTAssertNotEqual(sandboxedSettings.lastLeftDirectory, ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true))
        XCTAssertNotEqual(sandboxedSettings.lastRightDirectory, ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true))
        #endif
    }

    func testSidebarVisibilityDefaultAndRoundTrip() {
        XCTAssertTrue(settings.defaultSidebarVisible)
        XCTAssertTrue(settings.isSidebarVisible)

        settings.defaultSidebarVisible = false

        let reloaded = makeSettings()
        XCTAssertFalse(reloaded.defaultSidebarVisible)
        XCTAssertFalse(reloaded.isSidebarVisible)

        reloaded.isSidebarVisible = true
        XCTAssertTrue(makeSettings().defaultSidebarVisible)
    }

    func testTerminalVisibilityAndExperimentalEnablementDefaultAndRoundTrip() {
        XCTAssertFalse(settings.experimentalTerminalEnabled)
        XCTAssertFalse(settings.defaultTerminalVisible)
        XCTAssertFalse(settings.isTerminalVisible)

        settings.defaultTerminalVisible = true
        XCTAssertFalse(makeSettings().defaultTerminalVisible)

        settings.experimentalTerminalEnabled = true
        settings.defaultTerminalVisible = true

        let reloaded = makeSettings()
        XCTAssertTrue(reloaded.experimentalTerminalEnabled)
        XCTAssertTrue(reloaded.defaultTerminalVisible)
        XCTAssertTrue(reloaded.isTerminalVisible)

        reloaded.experimentalTerminalEnabled = false
        XCTAssertFalse(makeSettings().experimentalTerminalEnabled)
        XCTAssertFalse(makeSettings().defaultTerminalVisible)
    }

    func testManualTerminalVisibilityDoesNotChangeDefaultStartupVisibility() {
        settings.experimentalTerminalEnabled = true
        XCTAssertFalse(settings.defaultTerminalVisible)

        settings.isTerminalVisible = true

        XCTAssertTrue(settings.isTerminalVisible)
        XCTAssertFalse(settings.defaultTerminalVisible)
        XCTAssertFalse(makeSettings().defaultTerminalVisible)

        settings.defaultTerminalVisible = true
        settings.isTerminalVisible = false

        XCTAssertFalse(settings.isTerminalVisible)
        XCTAssertTrue(settings.defaultTerminalVisible)
        XCTAssertTrue(makeSettings().defaultTerminalVisible)
    }

    func testSinglePaneModeDefaultAndRoundTrip() {
        XCTAssertFalse(settings.defaultSinglePaneMode)

        settings.defaultSinglePaneMode = true

        XCTAssertTrue(makeSettings().defaultSinglePaneMode)
    }

    func testHiddenFileDefaultAndRoundTrip() {
        XCTAssertFalse(settings.showHiddenFilesByDefault)

        settings.showHiddenFilesByDefault = true

        XCTAssertTrue(makeSettings().showHiddenFilesByDefault)
    }

    func testDefaultSortDescriptorDefaultAndRoundTrip() {
        XCTAssertEqual(settings.defaultSortDescriptor, FileSortDescriptor())

        let descriptor = FileSortDescriptor(key: .modified, ascending: false)
        settings.defaultSortDescriptor = descriptor

        XCTAssertEqual(makeSettings().defaultSortDescriptor, descriptor)
    }

    func testConfirmationPreferencesDefaultAndRoundTrip() {
        XCTAssertTrue(settings.confirmCopyOperations)
        XCTAssertTrue(settings.confirmMoveOperations)
        XCTAssertTrue(settings.confirmDeleteOperations)
        XCTAssertFalse(settings.permanentlyDeleteInsteadOfTrash)

        settings.confirmCopyOperations = false
        settings.confirmMoveOperations = false
        settings.confirmDeleteOperations = false
        settings.permanentlyDeleteInsteadOfTrash = true

        let reloaded = makeSettings()
        XCTAssertFalse(reloaded.confirmCopyOperations)
        XCTAssertFalse(reloaded.confirmMoveOperations)
        XCTAssertFalse(reloaded.confirmDeleteOperations)
        XCTAssertTrue(reloaded.permanentlyDeleteInsteadOfTrash)
    }

    func testExperimentalSandboxPreferenceDefaultAndRoundTrip() {
        XCTAssertFalse(settings.experimentalSandboxEnabled)

        settings.experimentalSandboxEnabled = false
        XCTAssertFalse(makeSettings().experimentalSandboxEnabled)

        settings.experimentalSandboxEnabled = true
        #if DEBUG
        XCTAssertTrue(makeSettings().experimentalSandboxEnabled)
        #else
        XCTAssertFalse(makeSettings().experimentalSandboxEnabled)
        #endif
    }

    func testExperimentalSandboxFlagUsesSharedDefaultingLogic() {
        XCTAssertEqual(
            settings.experimentalSandboxEnabled,
            ExperimentalFlags.isSandboxRestrictionEnabled(defaults: fixture.defaults)
        )
    }

    func testSettingsJSONExportHandlesExperimentalSandboxForBuildConfiguration() throws {
        settings.experimentalSandboxEnabled = true

        let jsonURL = try settings.writeSettingsJSON()
        XCTAssertEqual(jsonURL, settingsJSONURL)

        let document = try decodedSettingsJSONDocument(at: jsonURL)
        let exportedSandboxValue = document["settings"]?["experimentalSandboxEnabled"] as? Bool

        #if DEBUG
        XCTAssertEqual(exportedSandboxValue, true)
        #else
        XCTAssertNil(exportedSandboxValue)
        #endif
    }

    func testLegacyExperimentalSandboxJSONImportIsIgnoredInRelease() throws {
        try writeSettingsJSON(
            settings: [
                "defaultSidebarVisible": false,
                "experimentalSandboxEnabled": true
            ]
        )
        fixture.defaults.removeObject(forKey: "settingsJSONLastImportedModificationTime")
        fixture.defaults.removeObject(forKey: "defaultSidebarVisible")
        fixture.defaults.removeObject(forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)

        let importedSettings = makeSettings()

        XCTAssertFalse(importedSettings.defaultSidebarVisible)
        #if DEBUG
        XCTAssertTrue(importedSettings.experimentalSandboxEnabled)
        #else
        XCTAssertFalse(importedSettings.experimentalSandboxEnabled)
        XCTAssertNil(fixture.defaults.object(forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey))

        let reexportedDocument = try decodedSettingsJSONDocument(at: settingsJSONURL)
        XCTAssertNil(reexportedDocument["settings"]?["experimentalSandboxEnabled"])
        #endif
    }

    func testFileColorSchemeDefaultAndRoundTrip() {
        assertColor(settings.fileColorScheme.color(for: .folder), equals: FileColorScheme.default.color(for: .folder))
        assertColor(settings.fileColorScheme.color(for: .sourceCode), equals: FileColorScheme.default.color(for: .sourceCode))

        let scheme = FileColorScheme(colors: [
            .folder: NSColor(deviceRed: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            .sourceCode: NSColor(deviceRed: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        ])
        settings.fileColorScheme = scheme

        let reloaded = makeSettings().fileColorScheme
        assertColor(reloaded.color(for: .folder), equals: scheme.color(for: .folder))
        assertColor(reloaded.color(for: .sourceCode), equals: scheme.color(for: .sourceCode))
    }

    private func assertColor(_ actual: NSColor, equals expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualRGB = actual.usingColorSpace(.deviceRGB),
              let expectedRGB = expected.usingColorSpace(.deviceRGB) else {
            XCTFail("Expected colors to convert to device RGB", file: file, line: line)
            return
        }

        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.001, file: file, line: line)
    }

    private func decodedSettingsJSONDocument(at url: URL) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let settings = json?["settings"] as? [String: Any] else {
            XCTFail("Expected settings JSON document at \(url.path)")
            return [:]
        }
        return ["settings": settings]
    }

    private var settingsJSONURL: URL {
        settingsJSONFixture.path("Settings.json")
    }

    private func makeSettings() -> SettingsService {
        SettingsService(
            defaults: fixture.defaults,
            jsonSettingsURLProvider: { [settingsJSONURL] in settingsJSONURL }
        )
    }

    private func writeSettingsJSON(settings: [String: Any]) throws {
        let document: [String: Any] = [
            "version": 1,
            "settings": settings
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsJSONURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: settingsJSONURL.path
        )
    }

}

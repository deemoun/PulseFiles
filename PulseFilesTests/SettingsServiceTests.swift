import AppKit
import XCTest
@testable import PulseFiles

final class SettingsServiceTests: XCTestCase {
    private var fixture: IsolatedDefaultsFixture!
    private var settings: SettingsService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try IsolatedDefaultsFixture(prefix: "SettingsServiceTests", testCase: self)
        settings = SettingsService(defaults: fixture.defaults)
    }

    override func tearDownWithError() throws {
        fixture.cleanup()
        settings = nil
        fixture = nil
        try super.tearDownWithError()
    }

    func testDirectorySettingsDefaultAndRoundTrip() {
        XCTAssertEqual(settings.lastLeftDirectory, FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertEqual(settings.lastRightDirectory, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
        XCTAssertNil(settings.startupLeftDirectory)
        XCTAssertNil(settings.startupRightDirectory)
        XCTAssertEqual(settings.launchLeftDirectory, settings.lastLeftDirectory)
        XCTAssertEqual(settings.launchRightDirectory, settings.lastRightDirectory)

        let lastLeft = ExperimentalFlags.appSandboxRoot.appendingPathComponent("Projects", isDirectory: true)
        let lastRight = ExperimentalFlags.appSandboxRoot.appendingPathComponent("Downloads", isDirectory: true)
        let startupLeft = ExperimentalFlags.appSandboxRoot.appendingPathComponent("Startup Left", isDirectory: true)
        let startupRight = ExperimentalFlags.appSandboxRoot.appendingPathComponent("Startup Right", isDirectory: true)

        settings.lastLeftDirectory = lastLeft
        settings.lastRightDirectory = lastRight
        settings.startupLeftDirectory = startupLeft
        settings.startupRightDirectory = startupRight

        let reloaded = SettingsService(defaults: fixture.defaults)
        XCTAssertEqual(reloaded.lastLeftDirectory, lastLeft)
        XCTAssertEqual(reloaded.lastRightDirectory, lastRight)
        XCTAssertEqual(reloaded.startupLeftDirectory, startupLeft)
        XCTAssertEqual(reloaded.startupRightDirectory, startupRight)
        XCTAssertEqual(reloaded.launchLeftDirectory, startupLeft)
        XCTAssertEqual(reloaded.launchRightDirectory, startupRight)

        reloaded.startupLeftDirectory = nil
        reloaded.startupRightDirectory = nil
        XCTAssertNil(SettingsService(defaults: fixture.defaults).startupLeftDirectory)
        XCTAssertNil(SettingsService(defaults: fixture.defaults).startupRightDirectory)
    }

    func testSidebarVisibilityDefaultAndRoundTrip() {
        XCTAssertTrue(settings.defaultSidebarVisible)
        XCTAssertTrue(settings.isSidebarVisible)

        settings.defaultSidebarVisible = false

        let reloaded = SettingsService(defaults: fixture.defaults)
        XCTAssertFalse(reloaded.defaultSidebarVisible)
        XCTAssertFalse(reloaded.isSidebarVisible)

        reloaded.isSidebarVisible = true
        XCTAssertTrue(SettingsService(defaults: fixture.defaults).defaultSidebarVisible)
    }

    func testTerminalVisibilityAndExperimentalEnablementDefaultAndRoundTrip() {
        XCTAssertFalse(settings.experimentalTerminalEnabled)
        XCTAssertFalse(settings.defaultTerminalVisible)
        XCTAssertFalse(settings.isTerminalVisible)

        settings.defaultTerminalVisible = true
        XCTAssertFalse(SettingsService(defaults: fixture.defaults).defaultTerminalVisible)

        settings.experimentalTerminalEnabled = true
        settings.defaultTerminalVisible = true

        let reloaded = SettingsService(defaults: fixture.defaults)
        XCTAssertTrue(reloaded.experimentalTerminalEnabled)
        XCTAssertTrue(reloaded.defaultTerminalVisible)
        XCTAssertTrue(reloaded.isTerminalVisible)

        reloaded.experimentalTerminalEnabled = false
        XCTAssertFalse(SettingsService(defaults: fixture.defaults).experimentalTerminalEnabled)
        XCTAssertFalse(SettingsService(defaults: fixture.defaults).defaultTerminalVisible)
    }

    func testSinglePaneModeDefaultAndRoundTrip() {
        XCTAssertFalse(settings.defaultSinglePaneMode)

        settings.defaultSinglePaneMode = true

        XCTAssertTrue(SettingsService(defaults: fixture.defaults).defaultSinglePaneMode)
    }

    func testHiddenFileDefaultAndRoundTrip() {
        XCTAssertFalse(settings.showHiddenFilesByDefault)

        settings.showHiddenFilesByDefault = true

        XCTAssertTrue(SettingsService(defaults: fixture.defaults).showHiddenFilesByDefault)
    }

    func testDefaultSortDescriptorDefaultAndRoundTrip() {
        XCTAssertEqual(settings.defaultSortDescriptor, FileSortDescriptor())

        let descriptor = FileSortDescriptor(key: .modified, ascending: false)
        settings.defaultSortDescriptor = descriptor

        XCTAssertEqual(SettingsService(defaults: fixture.defaults).defaultSortDescriptor, descriptor)
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

        let reloaded = SettingsService(defaults: fixture.defaults)
        XCTAssertFalse(reloaded.confirmCopyOperations)
        XCTAssertFalse(reloaded.confirmMoveOperations)
        XCTAssertFalse(reloaded.confirmDeleteOperations)
        XCTAssertTrue(reloaded.permanentlyDeleteInsteadOfTrash)
    }

    func testExperimentalSandboxPreferenceDefaultAndRoundTrip() {
        XCTAssertFalse(settings.experimentalSandboxEnabled)

        settings.experimentalSandboxEnabled = false
        XCTAssertFalse(SettingsService(defaults: fixture.defaults).experimentalSandboxEnabled)

        settings.experimentalSandboxEnabled = true
        #if DEBUG
        XCTAssertTrue(SettingsService(defaults: fixture.defaults).experimentalSandboxEnabled)
        #else
        XCTAssertFalse(SettingsService(defaults: fixture.defaults).experimentalSandboxEnabled)
        #endif
    }

    func testExperimentalSandboxFlagUsesSharedDefaultingLogic() {
        XCTAssertEqual(
            settings.experimentalSandboxEnabled,
            ExperimentalFlags.isSandboxRestrictionEnabled(defaults: fixture.defaults)
        )
    }

    func testFileColorSchemeDefaultAndRoundTrip() {
        assertColor(settings.fileColorScheme.color(for: .folder), equals: FileColorScheme.default.color(for: .folder))
        assertColor(settings.fileColorScheme.color(for: .sourceCode), equals: FileColorScheme.default.color(for: .sourceCode))

        let scheme = FileColorScheme(colors: [
            .folder: NSColor(deviceRed: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            .sourceCode: NSColor(deviceRed: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        ])
        settings.fileColorScheme = scheme

        let reloaded = SettingsService(defaults: fixture.defaults).fileColorScheme
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
}

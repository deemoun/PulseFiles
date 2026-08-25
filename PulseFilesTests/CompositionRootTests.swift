import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class CompositionRootTests: XCTestCase {
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

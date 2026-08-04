import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class MainCommandValidationUITests: XCTestCase {
    func testEveryMenuCommandValidationMatchesItsRouterRoute() throws {
        let dependencies = MainWindowDependencies.production(accessPolicy: .current)
        let controller = MainWindowViewController(settings: SettingsService(), accessPolicy: .current, dependencies: dependencies, workflowDependencies: .production(from: dependencies, accessPolicy: .current))
        controller.loadViewIfNeeded()
        let menu = AppDelegate(launchArguments: ["PulseFiles"]).buildMainMenu()

        for command in MainCommand.allCases {
            guard let item = menu.flattenedItems.first(where: {
                $0.identifier?.rawValue == AccessibilityIdentifiers.Command.menuItem(command)
            }) else {
                continue // Some commands intentionally have no menu entry.
            }
            let expectedEnabled: Bool
            if case .disabled = controller.commandRouteForValidation(command) {
                expectedEnabled = false
            } else {
                expectedEnabled = true
            }
            XCTAssertEqual(controller.validateMenuItem(item), expectedEnabled, "Menu validation diverged for \(command)")
        }
    }

    func testInitialLastTabAndMissingFocusAreDisabledByAppKitValidation() throws {
        let dependencies = MainWindowDependencies.production(accessPolicy: .current)
        let controller = MainWindowViewController(settings: SettingsService(), accessPolicy: .current, dependencies: dependencies, workflowDependencies: .production(from: dependencies, accessPolicy: .current))
        controller.loadViewIfNeeded()
        let menu = AppDelegate(launchArguments: ["PulseFiles"]).buildMainMenu()

        for command in [MainCommand.closeTab, .open, .rename, .quickLook] {
            let item = try XCTUnwrap(menu.flattenedItems.first {
                $0.identifier?.rawValue == AccessibilityIdentifiers.Command.menuItem(command)
            })
            XCTAssertFalse(controller.validateMenuItem(item), "\(command) must be disabled without the required tab or focus")
        }
    }
}

private extension NSMenu {
    var flattenedItems: [NSMenuItem] {
        items.flatMap { [$0] + ($0.submenu?.flattenedItems ?? []) }
    }
}

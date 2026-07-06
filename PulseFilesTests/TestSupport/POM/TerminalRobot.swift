import Foundation
import XCTest
@testable import PulseFiles

/// Logic-backed terminal robot for the SwiftPM unit test target.
///
/// This checks the opt-in settings contract today; future UI-backed coverage
/// should keep the same safety-focused page-object vocabulary.
final class TerminalRobot: TerminalPageObject {
    private let settings: SettingsService

    var panelAccessibilityIdentifier: String { AccessibilityIdentifiers.Terminal.panel }
    var toggleAccessibilityIdentifier: String { AccessibilityIdentifiers.Toolbar.terminalToggle }

    init(settings: SettingsService) {
        self.settings = settings
    }

    @discardableResult
    func setExperimentalTerminalEnabled(_ enabled: Bool) -> Self {
        settings.experimentalTerminalEnabled = enabled
        return self
    }

    @discardableResult
    func setVisibleByDefault(_ visible: Bool) -> Self {
        settings.defaultTerminalVisible = visible
        return self
    }

    @discardableResult
    func acknowledgeWarning() -> Self {
        settings.hasAcknowledgedTerminalWarning = true
        return self
    }

    @discardableResult
    func expectEnabled(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(settings.experimentalTerminalEnabled, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectVisibleByDefault(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(settings.defaultTerminalVisible, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectWarningAcknowledged(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(settings.hasAcknowledgedTerminalWarning, expected, file: file, line: line)
        return self
    }
}

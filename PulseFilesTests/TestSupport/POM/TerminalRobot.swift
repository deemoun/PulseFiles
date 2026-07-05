import Foundation
import XCTest
@testable import PulseFiles

final class TerminalRobot {
    private let settings: SettingsService

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

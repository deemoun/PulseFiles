import Foundation
import XCTest
@testable import PulseFiles

final class CommandBarRobot {
    typealias CommandHandler = (MainCommand) -> Void

    private var handler: CommandHandler?
    private(set) var executedCommands: [MainCommand] = []

    init(handler: CommandHandler? = nil) {
        self.handler = handler
    }

    @discardableResult
    func onExecute(_ handler: @escaping CommandHandler) -> Self {
        self.handler = handler
        return self
    }

    @discardableResult
    func execute(_ action: CommandBarAction) -> Self {
        let command = MainCommand(commandBarAction: action)
        executedCommands.append(command)
        handler?(command)
        return self
    }

    @discardableResult
    func expectAction(_ action: CommandBarAction, mapsTo expected: MainCommand, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(MainCommand(commandBarAction: action), expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectExecuted(_ expected: [MainCommand], file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(executedCommands, expected, file: file, line: line)
        return self
    }
}

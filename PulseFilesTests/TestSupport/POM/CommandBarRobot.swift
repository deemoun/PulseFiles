// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import PulseFiles

/// Logic-backed command-bar robot for the SwiftPM unit test target.
///
/// This verifies command mapping without UI automation; a future
/// `CommandBarPage` should drive the same actions through AppKit accessibility.
final class CommandBarRobot: CommandBarPageObject {
    typealias CommandHandler = (MainCommand) -> Void

    private var handler: CommandHandler?
    private(set) var isOpen = false
    private(set) var executedCommands: [MainCommand] = []

    var fieldAccessibilityIdentifier: String { AccessibilityIdentifiers.CommandBar.field }
    var listAccessibilityIdentifier: String { AccessibilityIdentifiers.CommandBar.list }

    init(handler: CommandHandler? = nil) {
        self.handler = handler
    }

    @discardableResult
    func open() -> Self {
        isOpen = true
        return self
    }

    @discardableResult
    func typeKnownCommand(_ action: CommandBarAction) -> Self {
        execute(action)
    }

    @discardableResult
    func expectOpen(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(isOpen, expected, file: file, line: line)
        return self
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
    func expectIntrinsicWidthLayoutPriorities(file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(CommandBarAction.view.commandBarVisibilityPriority, .mustHold, file: file, line: line)
        XCTAssertEqual(CommandBarAction.copy.commandBarVisibilityPriority, .mustHold, file: file, line: line)
        XCTAssertEqual(CommandBarAction.move.commandBarVisibilityPriority, .mustHold, file: file, line: line)
        XCTAssertEqual(CommandBarAction.delete.commandBarVisibilityPriority, .mustHold, file: file, line: line)
        XCTAssertLessThan(CommandBarAction.rename.commandBarVisibilityPriority.rawValue, CommandBarAction.delete.commandBarVisibilityPriority.rawValue, file: file, line: line)
        return self
    }

    @discardableResult
    func expectLocalizedTooltips(file: StaticString = #filePath, line: UInt = #line) -> Self {
        CommandBarAction.allCases.forEach { action in
            XCTAssertEqual(action.localizedTooltip, "\(action.title) (\(action.shortcut))", file: file, line: line)
            XCTAssertNotEqual(action.localizedTooltip, action.rawValue, file: file, line: line)
        }
        return self
    }

    @discardableResult
    func expectDestructiveTreatment(file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(CommandBarAction.delete.isDestructive, file: file, line: line)
        XCTAssertFalse(CommandBarAction.copy.isDestructive, file: file, line: line)
        XCTAssertFalse(CommandBarAction.move.isDestructive, file: file, line: line)
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

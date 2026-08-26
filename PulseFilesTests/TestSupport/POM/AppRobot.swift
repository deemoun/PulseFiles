// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFiles

@MainActor
/// Logic-backed app robot for the SwiftPM unit test target.
///
/// This is intentionally not an `XCUIApplication` wrapper; keep its public
/// workflow names aligned with a future UI-backed `PulseFilesApplication`.
final class AppRobot: AppPageObject {
    struct Dependencies {
        let leftDirectory: URL
        let rightDirectory: URL
        let fileSystem: TestFileSystem
        let accessPolicy: SandboxFileAccessPolicy
        let defaults: UserDefaults

        init(
            leftDirectory: URL,
            rightDirectory: URL,
            fileSystem: TestFileSystem = TestFileSystem(),
            accessPolicy: SandboxFileAccessPolicy? = nil,
            defaults: UserDefaults = UserDefaults(suiteName: "PulseFilesTests.AppRobot.\(UUID().uuidString)")!
        ) {
            self.leftDirectory = leftDirectory
            self.rightDirectory = rightDirectory
            self.fileSystem = fileSystem
            self.accessPolicy = accessPolicy ?? SandboxFileAccessPolicy(isEnabled: true, rootURL: leftDirectory.deletingLastPathComponent())
            self.defaults = defaults
        }
    }

    let leftPane: FilePaneRobot
    let rightPane: FilePaneRobot
    let commandBar: CommandBarRobot
    let sidebar: SidebarRobot
    let terminal: TerminalRobot
    let settings: SettingsService
    let defaults: UserDefaults
    let fileSystem: TestFileSystem
    private(set) var activePaneID: PaneID
    private(set) var isLaunched = false
    private(set) var isSidebarVisible: Bool
    private(set) var pendingDestructiveConfirmation: MainCommand?
    private(set) var destructiveMutationCount = 0

    init(dependencies: Dependencies) {
        defaults = dependencies.defaults
        fileSystem = dependencies.fileSystem
        settings = SettingsService(defaults: dependencies.defaults)
        activePaneID = .left
        isSidebarVisible = SettingsService(defaults: dependencies.defaults).isSidebarVisible
        pendingDestructiveConfirmation = nil

        let leftViewModel = FilePaneViewModel(
            initialDirectory: dependencies.leftDirectory,
            fileSystem: dependencies.fileSystem,
            accessPolicy: dependencies.accessPolicy
        )
        let rightViewModel = FilePaneViewModel(
            initialDirectory: dependencies.rightDirectory,
            fileSystem: dependencies.fileSystem,
            accessPolicy: dependencies.accessPolicy
        )

        leftPane = FilePaneRobot(paneID: .left, viewModel: leftViewModel, isActive: true)
        rightPane = FilePaneRobot(paneID: .right, viewModel: rightViewModel)
        commandBar = CommandBarRobot()
        sidebar = SidebarRobot(
            bookmarkService: BookmarkService(defaults: dependencies.defaults),
            recentLocationService: RecentLocationService(defaults: dependencies.defaults)
        )
        terminal = TerminalRobot(settings: settings)
    }

    static func temporary(
        rootName: String = "PulseFilesAppRobot",
        fileSystem: TestFileSystem = TestFileSystem(),
        defaults: UserDefaults = UserDefaults(suiteName: "PulseFilesTests.AppRobot.\(UUID().uuidString)")!
    ) throws -> AppRobot {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(rootName)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let left = root.appendingPathComponent("Left", isDirectory: true)
        let right = root.appendingPathComponent("Right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        return AppRobot(dependencies: Dependencies(leftDirectory: left, rightDirectory: right, fileSystem: fileSystem, defaults: defaults))
    }


    @discardableResult
    func launch() async -> Self {
        isLaunched = true
        leftPane.viewModel.loadCurrentDirectory()
        rightPane.viewModel.loadCurrentDirectory()
        while leftPane.viewModel.isLoading || rightPane.viewModel.isLoading {
            await Task.yield()
        }
        return self
    }

    @discardableResult
    func toggleSidebar() -> Self {
        isSidebarVisible.toggle()
        settings.isSidebarVisible = isSidebarVisible
        return self
    }

    @discardableResult
    func requestDestructiveCommand(_ command: MainCommand) -> Self {
        guard command == .trash else {
            return self
        }
        pendingDestructiveConfirmation = command
        return self
    }

    @discardableResult
    func expectLaunched(file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(isLaunched, file: file, line: line)
        return self
    }

    @discardableResult
    func expectPanesVisible(file: StaticString = #filePath, line: UInt = #line) -> Self {
        leftPane.expectVisible(true, file: file, line: line)
        rightPane.expectVisible(true, file: file, line: line)
        return self
    }

    @discardableResult
    func expectSidebarVisible(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(isSidebarVisible, expected, file: file, line: line)
        XCTAssertEqual(settings.isSidebarVisible, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectPendingDestructiveConfirmation(_ expected: MainCommand?, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(pendingDestructiveConfirmation, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectDestructiveMutationCount(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(destructiveMutationCount, expected, file: file, line: line)
        return self
    }

    var activePane: FilePaneRobot {
        activePaneID == .left ? leftPane : rightPane
    }

    @discardableResult
    func switchPane() -> Self {
        setActivePane(activePaneID.opposite)
        return self
    }

    @discardableResult
    func setActivePane(_ paneID: PaneID) -> Self {
        activePaneID = paneID
        leftPane.markActive(paneID == .left)
        rightPane.markActive(paneID == .right)
        return self
    }

    @discardableResult
    func expectActivePane(_ expected: PaneID, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(activePaneID, expected, file: file, line: line)
        leftPane.expectActive(expected == .left, file: file, line: line)
        rightPane.expectActive(expected == .right, file: file, line: line)
        return self
    }
}

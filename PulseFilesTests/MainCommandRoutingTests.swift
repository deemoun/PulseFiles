import XCTest
import AppKit
@testable import PulseFiles

final class MainCommandRoutingTests: XCTestCase {
    func testSearchResultRouterRejectsStaleResult() {
        let root = URL(fileURLWithPath: "/root")
        let item = DescendantSearchItem(url: root.appendingPathComponent("gone.txt"), name: "gone.txt", pathContext: root.path, typeDescription: "File", isDirectory: false, isSymbolicLink: false)
        let route = SearchResultActionRouter().route(.open, item: item, root: root, canAccess: { _ in true }, fileExists: { _ in false })
        XCTAssertEqual(route, .unavailable)
    }
    func testViewerOwnsF3WhileReturnAndSpaceKeepExistingActions() {
        let router = MainCommandRouter()
        XCTAssertEqual(router.commandForKeyDown(keyCode: 99), .viewer)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 36), .open)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 49), .quickLook)
    }
    private let router = MainCommandRouter()

    func testActivePaneOnlyCommandsRouteToActivePaneSelection() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected])

        XCTAssertEqual(router.route(.open, in: state), .activePane(command: .open, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.openWith, in: state), .activePane(command: .openWith, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.rename, in: state), .activePane(command: .rename, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.duplicate, in: state), .activePane(command: .duplicate, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.getInfo, in: state), .activePane(command: .getInfo, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.trash, in: state), .activePane(command: .trash, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.reveal, in: state), .activePane(command: .reveal, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.refresh, in: state), .activePane(command: .refresh, pane: .left, urls: [selected]))
    }

    func testCopyAndMoveRouteSelectionToOppositePaneDirectory() {
        let selected = URL(fileURLWithPath: "/sandbox/right/report.pdf")
        let state = makeState(activePaneID: .right, rightSelection: [selected])
        let leftDirectory = URL(fileURLWithPath: "/sandbox/left", isDirectory: true)

        XCTAssertEqual(
            router.route(.copy, in: state),
            .crossPane(command: .copy, sourcePane: .right, destinationPane: .left, sourceURLs: [selected], destinationDirectory: leftDirectory)
        )
        XCTAssertEqual(
            router.route(.move, in: state),
            .crossPane(command: .move, sourcePane: .right, destinationPane: .left, sourceURLs: [selected], destinationDirectory: leftDirectory)
        )
    }

    func testCopyAndMoveAreDisabledInSinglePaneModeAndRestoreInDualPaneMode() {
        let selected = URL(fileURLWithPath: "/sandbox/right/report.pdf")
        let singlePaneState = makeState(activePaneID: .right, rightSelection: [selected], isSinglePaneMode: true)
        let dualPaneState = makeState(activePaneID: .right, rightSelection: [selected], isSinglePaneMode: false)
        let expectedDualPaneRoute = MainCommandRoute.crossPane(
            command: .copy,
            sourcePane: .right,
            destinationPane: .left,
            sourceURLs: [selected],
            destinationDirectory: URL(fileURLWithPath: "/sandbox/left", isDirectory: true)
        )

        for command in [MainCommand.copy, .move] {
            XCTAssertEqual(router.route(command, in: singlePaneState), .disabled(command: command, reason: .noOppositePane))
        }
        XCTAssertEqual(router.route(.copy, in: dualPaneState), expectedDualPaneRoute)
        XCTAssertEqual(
            router.route(.move, in: dualPaneState),
            .crossPane(
                command: .move,
                sourcePane: .right,
                destinationPane: .left,
                sourceURLs: [selected],
                destinationDirectory: URL(fileURLWithPath: "/sandbox/left", isDirectory: true)
            )
        )
    }

    func testTabSwitchingAlternatesBetweenLeftAndRightPanes() {
        XCTAssertEqual(router.route(.switchPane, in: makeState(activePaneID: .left)), .switchPane(to: .right))
        XCTAssertEqual(router.route(.switchPane, in: makeState(activePaneID: .right)), .switchPane(to: .left))
        XCTAssertEqual(router.commandForKeyDown(keyCode: 48), .switchPane)
        XCTAssertNil(router.commandForKeyDown(keyCode: 48, command: true), "Command-Tab belongs to the system app switcher.")
    }

    func testSelectionCommandsAreDisabledWhenNoSelectionExists() {
        let state = makeState(activePaneID: .left)

        for command in [MainCommand.openWith, .trash, .duplicate, .copy, .move, .copyToClipboard, .cutToClipboard] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .noSelection))
        }
        for command in [MainCommand.open, .viewer, .rename, .getInfo, .reveal, .quickLook] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .noFocusedItem))
        }
    }

    func testSelectionCommandsAreDisabledWhenSandboxRejectsSelectedURL() {
        let selected = URL(fileURLWithPath: "/outside-sandbox/secret.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected], sandboxAllowsSelectedURLs: false)

        for command in [MainCommand.open, .viewer, .openWith, .rename, .duplicate, .getInfo, .trash, .reveal, .copy, .move, .copyToClipboard, .cutToClipboard] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .sandboxRejectedSelection))
        }
    }

    func testFocusedItemCommandsRouteWithFocusedItemWithoutSelection() {
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.txt")
        let state = makeState(activePaneID: .left, leftFocusedURL: focused)

        for command in [MainCommand.open, .viewer, .rename, .reveal] {
            XCTAssertEqual(router.route(command, in: state), .activePane(command: command, pane: .left, urls: [focused]))
        }
    }

    func testFocusedItemCommandsAreDisabledWhenSelectionExistsButNoItemIsFocused() {
        let selected = URL(fileURLWithPath: "/sandbox/left/selected.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected], leftFocusedURL: .none)

        for command in [MainCommand.open, .viewer, .rename, .reveal] {
            XCTAssertEqual(router.route(command, in: state), .disabled(command: command, reason: .noFocusedItem))
        }
        XCTAssertEqual(router.route(.copy, in: state), .crossPane(command: .copy, sourcePane: .left, destinationPane: .right, sourceURLs: [selected], destinationDirectory: URL(fileURLWithPath: "/sandbox/right", isDirectory: true)))
    }

    func testSearchFieldFocusDoesNotStealStandardTextShortcuts() {
        XCTAssertNil(router.commandForKeyDown(keyCode: 0, command: true, isTextInputFocused: true), "Command-A should remain select-all in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 8, command: true, isTextInputFocused: true), "Command-C should remain copy text in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 7, command: true, isTextInputFocused: true), "Command-X should remain cut text in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 9, command: true, isTextInputFocused: true), "Command-V should remain paste in search text fields.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 120, isTextInputFocused: true), "F2 should not rename while editing search text.")
        XCTAssertNil(router.commandForKeyDown(keyCode: 49, isTextInputFocused: true), "Space should remain text input in search text fields.")
        XCTAssertEqual(router.commandForKeyDown(keyCode: 47, command: true, isTextInputFocused: true), .cancelOperation)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 50, command: true, isTextInputFocused: true), .toggleTerminal)
        for shortcut in [(0, false), (24, false), (27, false), (24, true), (27, true)] {
            XCTAssertNil(router.commandForKeyDown(keyCode: UInt16(shortcut.0), command: true, option: shortcut.1, isTextInputFocused: true))
        }
    }

    func testPatternAndExtensionShortcutsAreExactAndOutsideTextInput() {
        XCTAssertEqual(router.commandForKeyDown(keyCode: 0, command: true, option: true), .deselectAll)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 24, command: true), .selectByPattern)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 27, command: true), .deselectByPattern)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 24, command: true, option: true), .selectSameExtension)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 27, command: true, option: true), .deselectSameExtension)
    }

    func testSameExtensionCommandsHaveExplicitNoRealFocusedItemReason() {
        let state = makeState(activePaneID: .left)
        XCTAssertEqual(router.route(.selectSameExtension, in: state), .disabled(command: .selectSameExtension, reason: .noRealFocusedItem))
        XCTAssertEqual(router.route(.deselectSameExtension, in: state), .disabled(command: .deselectSameExtension, reason: .noRealFocusedItem))
    }

    func testDebugLogsRouteAsAlwaysEnabledCommand() {
        XCTAssertEqual(router.route(.debugLogs, in: makeState(activePaneID: .left)), .enabled(command: .debugLogs))
    }

    func testUndoRoutesOnlyWithRecoveryAndIsDisabledDuringActiveOperation() {
        XCTAssertEqual(router.route(.undo, in: makeState(activePaneID: .left)), .disabled(command: .undo, reason: .noUndoRecovery))
        XCTAssertEqual(router.route(.undo, in: makeState(activePaneID: .left, isFileOperationActive: true, hasUndoRecovery: true)), .disabled(command: .undo, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.undo, in: makeState(activePaneID: .left, hasUndoRecovery: true)), .enabled(command: .undo))
    }

    func testCancelOperationRoutesOnlyDuringActiveFileOperation() {
        XCTAssertEqual(router.commandForKeyDown(keyCode: 47, command: true), .cancelOperation)
        XCTAssertEqual(
            router.route(.cancelOperation, in: makeState(activePaneID: .left, isFileOperationActive: true)),
            .enabled(command: .cancelOperation)
        )
        XCTAssertEqual(
            router.route(.cancelOperation, in: makeState(activePaneID: .left, isFileOperationActive: false)),
            .disabled(command: .cancelOperation, reason: .noActiveFileOperation)
        )
    }

    func testSpaceRoutesToQuickLookFocusedItemOutsideTextInput() {
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.png")
        let state = makeState(activePaneID: .left, leftFocusedURL: focused)

        XCTAssertEqual(router.commandForKeyDown(keyCode: 49), .quickLook)
        XCTAssertEqual(router.route(.quickLook, in: state), .activePane(command: .quickLook, pane: .left, urls: [focused]))
    }

    func testF3ViewsAndF4OpensFocusedItem() {
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.txt")
        let state = makeState(activePaneID: .left, leftFocusedURL: focused)

        XCTAssertEqual(router.commandForKeyDown(keyCode: 99), .viewer)
        XCTAssertEqual(router.route(.viewer, in: state), .activePane(command: .viewer, pane: .left, urls: [focused]))
        XCTAssertEqual(router.commandForKeyDown(keyCode: 118), .open)
        XCTAssertEqual(router.route(.open, in: state), .activePane(command: .open, pane: .left, urls: [focused]))
    }

    func testReturnOpensFocusedItemInsteadOfStartingRename() {
        let focused = URL(fileURLWithPath: "/sandbox/left/focused-folder", isDirectory: true)
        let state = makeState(activePaneID: .left, leftFocusedURL: focused)

        XCTAssertEqual(router.commandForKeyDown(keyCode: 36), .open)
        XCTAssertEqual(router.route(.open, in: state), .activePane(command: .open, pane: .left, urls: [focused]))
        XCTAssertNotEqual(router.commandForKeyDown(keyCode: 36), .rename)
    }

    func testSupportedFunctionKeyShortcutsResolveToCommands() {
        let shortcuts: [(keyCode: UInt16, shift: Bool, command: MainCommand)] = [
            (122, false, .quickLocations), // F1
            (120, false, .rename), // F2
            (99, false, .viewer), // F3
            (118, false, .open), // F4
            (96, false, .copy), // F5
            (97, false, .move), // F6
            (98, false, .newFolder), // F7
            (98, true, .newFile), // Shift-F7
            (100, false, .trash) // F8
        ]

        for shortcut in shortcuts {
            let flags: NSEvent.ModifierFlags = shortcut.shift ? [.shift] : []
            let registrations = MainCommandShortcutRegistry.shortcuts.filter {
                $0.keyCode == shortcut.keyCode && $0.modifierFlags == flags
            }
            XCTAssertEqual(
                registrations.map(\.command),
                [shortcut.command],
                "Each documented function key must have exactly one expected command."
            )
            XCTAssertEqual(
                router.commandForKeyDown(keyCode: shortcut.keyCode, shift: shortcut.shift),
                shortcut.command
            )
        }
    }

    func testOpenViewerAndQuickLookShortcutsDoNotInterceptTextInput() {
        for keyCode: UInt16 in [99, 118, 36, 49] {
            XCTAssertNil(router.commandForKeyDown(keyCode: keyCode, isTextInputFocused: true))
        }
    }

    func testDeleteKeyVariantsAreHandledWithoutReachingTheFileTable() {
        XCTAssertEqual(router.commandForKeyDown(keyCode: 51), .parent)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 51, shift: true), .trash)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 51, command: true), .trash)

        for keyCode: UInt16 in [51, 117] {
            for modifiers in [(true, true, false, false), (false, false, true, false), (false, false, false, true)] {
                let command = router.commandForKeyDown(
                    keyCode: keyCode,
                    command: modifiers.0,
                    shift: modifiers.1,
                    option: modifiers.2,
                    control: modifiers.3
                )
                XCTAssertNil(command)
                XCTAssertTrue(router.shouldConsumeUnmappedKeyDown(keyCode: keyCode))
            }
        }
    }

    func testDeleteKeysRemainAvailableWhileEditingText() {
        XCTAssertNil(router.commandForKeyDown(keyCode: 51, shift: true, isTextInputFocused: true))
        XCTAssertFalse(router.shouldConsumeUnmappedKeyDown(keyCode: 51, isTextInputFocused: true))
        XCTAssertFalse(router.shouldConsumeUnmappedKeyDown(keyCode: 117, isTextInputFocused: true))
    }

    func testUnsupportedFunctionKeyCodesDoNotResolveToCommands() {
        for keyCode: UInt16 in [101, 109, 103, 111] { // F9, F10, F11, F12
            XCTAssertNil(router.commandForKeyDown(keyCode: keyCode))
        }
    }

    func testQuickLookUsesFocusedItemRatherThanSelection() {
        let selected = URL(fileURLWithPath: "/sandbox/left/selected.txt")
        let focused = URL(fileURLWithPath: "/sandbox/left/focused.png")
        let state = makeState(activePaneID: .left, leftSelection: [selected], leftFocusedURL: focused)

        XCTAssertEqual(router.route(.quickLook, in: state), .activePane(command: .quickLook, pane: .left, urls: [focused]))
    }

    func testClipboardShortcutsRouteWhenTextInputIsNotFocused() {
        XCTAssertEqual(router.commandForKeyDown(keyCode: 8, command: true), .copyToClipboard)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 7, command: true), .cutToClipboard)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 9, command: true), .pasteFromClipboard)
    }

    func testSelectionShortcutsAndRoutesRespectTextInputFocus() {
        let state = makeState(activePaneID: .left)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 0, command: true), .selectAll)
        XCTAssertEqual(router.commandForKeyDown(keyCode: 34, command: true, shift: true), .invertSelection)
        XCTAssertNil(router.commandForKeyDown(keyCode: 0, command: true, isTextInputFocused: true))
        XCTAssertEqual(router.route(.selectAll, in: state), .activePane(command: .selectAll, pane: .left, urls: []))
        XCTAssertEqual(router.route(.invertSelection, in: state), .activePane(command: .invertSelection, pane: .left, urls: []))
    }

    func testClipboardSelectionCommandsRouteToActivePane() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected])

        XCTAssertEqual(router.route(.copyToClipboard, in: state), .activePane(command: .copyToClipboard, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.cutToClipboard, in: state), .activePane(command: .cutToClipboard, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.pasteFromClipboard, in: state), .enabled(command: .pasteFromClipboard))
    }

    func testFileMutatingCommandsAreDisabledDuringActiveFileOperation() {
        let selected = URL(fileURLWithPath: "/sandbox/left/file.txt")
        let state = makeState(activePaneID: .left, leftSelection: [selected], isFileOperationActive: true)

        XCTAssertEqual(router.route(.newFile, in: state), .disabled(command: .newFile, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.newFolder, in: state), .disabled(command: .newFolder, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.rename, in: state), .disabled(command: .rename, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.duplicate, in: state), .disabled(command: .duplicate, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.copy, in: state), .disabled(command: .copy, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.move, in: state), .disabled(command: .move, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.cutToClipboard, in: state), .disabled(command: .cutToClipboard, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.pasteFromClipboard, in: state), .disabled(command: .pasteFromClipboard, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.trash, in: state), .disabled(command: .trash, reason: .fileOperationInProgress))
        XCTAssertEqual(router.route(.cancelOperation, in: state), .enabled(command: .cancelOperation))
        XCTAssertEqual(router.route(.refresh, in: state), .activePane(command: .refresh, pane: .left, urls: [selected]))
        XCTAssertEqual(router.route(.toggleSidebar, in: state), .enabled(command: .toggleSidebar))
        XCTAssertEqual(router.route(.toggleTerminal, in: state), .enabled(command: .toggleTerminal))
        XCTAssertEqual(router.route(.goToFolder, in: state), .enabled(command: .goToFolder))
    }

    private func makeState(
        activePaneID: PaneID,
        leftSelection: [URL] = [],
        rightSelection: [URL] = [],
        leftFocusedURL: URL?? = nil,
        rightFocusedURL: URL?? = nil,
        isSinglePaneMode: Bool = false,
        isFileOperationActive: Bool = false,
        sandboxAllowsSelectedURLs: Bool = true,
        hasUndoRecovery: Bool = false
    ) -> MainCommandRoutingState {
        MainCommandRoutingState(
            activePaneID: activePaneID,
            leftPane: MainCommandRoutingPane(
                id: .left,
                currentDirectory: URL(fileURLWithPath: "/sandbox/left", isDirectory: true),
                selectedURLs: leftSelection,
                focusedURL: leftFocusedURL ?? leftSelection.first
            ),
            rightPane: MainCommandRoutingPane(
                id: .right,
                currentDirectory: URL(fileURLWithPath: "/sandbox/right", isDirectory: true),
                selectedURLs: rightSelection,
                focusedURL: rightFocusedURL ?? rightSelection.first
            ),
            isSinglePaneMode: isSinglePaneMode,
            isFileOperationActive: isFileOperationActive,
            sandboxAllowsSelectedURLs: sandboxAllowsSelectedURLs,
            hasUndoRecovery: hasUndoRecovery
        )
    }
}

final class MainCommandDestinationResolverTests: XCTestCase {
    private let sandboxRoot = URL(fileURLWithPath: "/tmp/PulseFilesSandbox", isDirectory: true)

    func testReleaseDestinationsUseSystemLocationsEvenWhenSandboxPreferenceIsRestricted() {
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .home, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: false),
            FileManager.default.homeDirectoryForCurrentUser
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .downloads, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: false),
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .applications, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: false),
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
                ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        )
    }

    func testDebugRestrictedDestinationsPreserveSandboxRootBehavior() {
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .home, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: true),
            sandboxRoot
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .downloads, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: true),
            sandboxRoot.appendingPathComponent("Downloads", isDirectory: true)
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .applications, sandboxRestricted: true, sandboxRoot: sandboxRoot, isDebugBuild: true),
            sandboxRoot
        )
    }

    func testDebugUnrestrictedDestinationsUseSystemLocations() {
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .home, sandboxRestricted: false, sandboxRoot: sandboxRoot, isDebugBuild: true),
            FileManager.default.homeDirectoryForCurrentUser
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .downloads, sandboxRestricted: false, sandboxRoot: sandboxRoot, isDebugBuild: true),
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        )
        XCTAssertEqual(
            MainCommandDestinationResolver.destination(for: .applications, sandboxRestricted: false, sandboxRoot: sandboxRoot, isDebugBuild: true),
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
                ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        )
    }
}

final class ScratchDirectoryCommandRoutingTests: XCTestCase {
    private let router = ScratchDirectoryCommandRouter()
    private let scratch = URL(fileURLWithPath: "/workspace/scratch", isDirectory: true)

    func testConfiguredAccessibleFolderRoutesToNavigation() {
        XCTAssertEqual(router.route(configuredDirectory: scratch, canAccess: { _ in true }), .navigate(scratch))
    }

    func testUnconfiguredFolderRoutesToConfigurationPrompt() {
        XCTAssertEqual(router.route(configuredDirectory: nil, canAccess: { _ in true }), .promptForConfiguration)
    }

    func testInaccessibleFolderRoutesToAccessRecovery() {
        XCTAssertEqual(router.route(configuredDirectory: scratch, canAccess: { _ in false }), .requestAccess(scratch))
    }

    func testCancelledAccessRecoveryDoesNotRouteToNavigation() {
        XCTAssertEqual(router.routeAfterAccessRecovery(to: scratch, wasGranted: false), .cancelled)
    }

    func testScratchShortcutSupportsActiveAndAlternatePaneConventions() {
        let commandRouter = MainCommandRouter()
        XCTAssertEqual(commandRouter.commandForKeyDown(keyCode: 5, command: true, control: true), .scratchDirectory)
        XCTAssertEqual(commandRouter.commandForKeyDown(keyCode: 5, command: true, option: true, control: true), .scratchDirectory)
        XCTAssertNil(commandRouter.commandForKeyDown(keyCode: 5, command: true, control: true, isTextInputFocused: true))
    }
}

final class MainMenuConstructionTests: XCTestCase {
    func testCompleteMainMenuHasNoShortcutConflictsAndMatchesRegistry() throws {
        let suiteName = "MainMenuConstructionTests.shortcutAudit"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let menu = AppDelegate(
            launchArguments: ["PulseFiles", AppDelegate.editSettingsJSONDebugLaunchArgument],
            userDefaults: defaults
        ).buildMainMenu()
        let menuItems = menu.flattenedItems.filter { !$0.keyEquivalent.isEmpty }

        struct Chord: Hashable {
            let key: String
            let modifiers: UInt
        }
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        var owners: [Chord: Set<String>] = [:]
        for item in menuItems {
            let chord = Chord(
                key: item.keyEquivalent.lowercased(),
                modifiers: item.keyEquivalentModifierMask.intersection(relevantModifiers).rawValue
            )
            let command = MainCommand.allCases.first {
                item.identifier?.rawValue == AccessibilityIdentifiers.Command.menuItem($0)
            }
            let owner = command.map { "MainCommand.\($0)" }
                ?? item.action.map { "standard.\(NSStringFromSelector($0))" }
                ?? "menu.\(item.title)"
            owners[chord, default: []].insert(owner)

            if let command {
                let registrations = MainCommandShortcutRegistry.shortcuts.filter {
                    $0.command == command
                        && $0.keyEquivalent.lowercased() == chord.key
                        && $0.modifierFlags.intersection(relevantModifiers).rawValue == chord.modifiers
                }
                XCTAssertFalse(registrations.isEmpty, "Menu shortcut for \(command) is absent from the registry.")
            }
        }

        for (chord, chordOwners) in owners {
            XCTAssertEqual(chordOwners.count, 1, "Menu chord \(chord) maps to different commands: \(chordOwners)")
        }

        let minimize = try XCTUnwrap(menu.flattenedItems.first { $0.action == #selector(NSWindow.performMiniaturize(_:)) })
        XCTAssertEqual(minimize.keyEquivalent, "m")
        XCTAssertEqual(minimize.keyEquivalentModifierMask.intersection(relevantModifiers), [.command])
        XCTAssertFalse(MainCommandShortcutRegistry.shortcuts.contains {
            $0.command == .move && $0.keyEquivalent.lowercased() == "m" && $0.modifierFlags.contains(.command)
        })
    }

    func testOrthodoxMoveShortcutLabelsStaySynchronized() throws {
        XCTAssertEqual(MainCommandShortcutRegistry.shortcut(for: .move).displayLabel, "F6")
        XCTAssertEqual(CommandBarAction.move.shortcut, "F6")

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let expectedFragments: [(String, String)] = [
            ("README.md", "| F5 / F6 | Copy / move the selection to the opposite pane |"),
            ("PulseFiles/Resources/en.lproj/Localizable.strings", "F5 or F6 — Copy or move the selection to the opposite pane"),
            ("PulseFiles/Resources/ru.lproj/Localizable.strings", "F5 или F6 — копировать или переместить выбранное в другую панель")
        ]
        for (relativePath, fragment) in expectedFragments {
            let contents = try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertTrue(contents.contains(fragment), "\(relativePath) must document the F6 Move shortcut.")
        }
    }

    func testScratchFolderCommandIsAvailableFromGoMenu() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.scratchFolder")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.scratchFolder")

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Go to Scratch Folder"))
    }

    func testDebugLogsMenuItemIsAvailableFromWindowMenu() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.debugLogs")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.debugLogs")

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Debug Logs…"))
    }

    func testOpenWithMenuItemIsAvailableFromFileMenu() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.openWith")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.openWith")

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Open With…"))
    }

    func testSupportLinksAreAvailableFromHelpMenu() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.supportLinks")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.supportLinks")

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Get Support"))
        XCTAssertTrue(menu.containsItem(titled: "Privacy Policy"))
        XCTAssertTrue(menu.containsItem(titled: "Report an Issue"))
    }

    func testEditSettingsJSONMenuItemIsHiddenByDefault() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.default")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.default")

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertFalse(menu.containsItem(titled: "Edit Settings JSON…"))
    }

    func testEditSettingsJSONMenuItemIsShownWithDebugLaunchArgument() {
        let defaults = UserDefaults(suiteName: "MainMenuConstructionTests.launchArgument")!
        defaults.removePersistentDomain(forName: "MainMenuConstructionTests.launchArgument")

        let menu = AppDelegate(
            launchArguments: ["PulseFiles", AppDelegate.editSettingsJSONDebugLaunchArgument],
            userDefaults: defaults
        ).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Edit Settings JSON…"))
    }

    func testEditSettingsJSONMenuItemIsShownWithDebugDefaultsFlag() {
        let suiteName = "MainMenuConstructionTests.defaultsFlag"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: AppDelegate.editSettingsJSONDebugDefaultsKey)

        let menu = AppDelegate(launchArguments: ["PulseFiles"], userDefaults: defaults).buildMainMenu()

        XCTAssertTrue(menu.containsItem(titled: "Edit Settings JSON…"))
    }
}

private extension NSMenu {
    var flattenedItems: [NSMenuItem] {
        items.flatMap { item in [item] + (item.submenu?.flattenedItems ?? []) }
    }

    func containsItem(titled title: String) -> Bool {
        items.contains { item in
            item.title == title || item.submenu?.containsItem(titled: title) == true
        }
    }
}

extension MainCommandRoutingTests {
    func testRegistryContainsEveryMainCommand() {
        XCTAssertEqual(Set(MainCommandShortcutRegistry.shortcuts.map(\.command)), Set(MainCommand.allCases))
    }

    func testEveryRegisteredKeyboardShortcutResolvesToItsCommand() {
        for shortcut in MainCommandShortcutRegistry.shortcuts where MainCommandShortcutRegistry.hasKeyboardShortcut(shortcut) {
            let result = router.commandForKeyDown(
                keyCode: shortcut.keyCode,
                command: shortcut.modifierFlags.contains(.command),
                shift: shortcut.modifierFlags.contains(.shift),
                option: shortcut.modifierFlags.contains(.option),
                control: shortcut.modifierFlags.contains(.control),
                isTextInputFocused: shortcut.scope == .textInputSafe
            )
            XCTAssertEqual(result, shortcut.command, "Expected \(shortcut.displayLabel) to resolve to \(shortcut.command).")
        }
    }

    func testRegisteredKeyboardChordsDoNotConflict() {
        let keyboardShortcuts = MainCommandShortcutRegistry.shortcuts.filter(MainCommandShortcutRegistry.hasKeyboardShortcut)
        for (index, shortcut) in keyboardShortcuts.enumerated() {
            let duplicates = keyboardShortcuts.dropFirst(index + 1).filter {
                $0.keyCode == shortcut.keyCode && $0.modifierFlags == shortcut.modifierFlags
            }
            XCTAssertTrue(duplicates.isEmpty, "Conflicting keyboard shortcut for \(shortcut.displayLabel).")
        }
    }

    func testAuthoritativeSevenSortShortcutsAndEighthMenuOnlyCriterion() {
        let commands: [MainCommand] = [.sortByName, .sortByExtension, .sortByKind, .sortBySize, .sortByModified, .sortByCreated, .sortByAdded]
        for (offset, command) in commands.enumerated() {
            let shortcut = MainCommandShortcutRegistry.shortcut(for: command)
            XCTAssertEqual(shortcut.keyEquivalent, String(offset + 1))
            XCTAssertEqual(shortcut.modifierFlags, [.control, .command])
        }
        XCTAssertFalse(MainCommandShortcutRegistry.hasKeyboardShortcut(MainCommandShortcutRegistry.shortcut(for: .sortByAccessed)))
    }

    func testEveryCommandBarShortcutHasARegisteredHandler() {
        for action in CommandBarAction.allCases {
            let command = MainCommand(commandBarAction: action)
            XCTAssertFalse(action.shortcut.isEmpty, "\(action) needs a displayed shortcut.")
            XCTAssertTrue(
                MainCommandShortcutRegistry.shortcuts.contains(where: {
                    $0.command == command && MainCommandShortcutRegistry.hasKeyboardShortcut($0)
                }),
                "\(action) displays \(action.shortcut), but \(command) has no keyboard handler."
            )
        }
    }
}

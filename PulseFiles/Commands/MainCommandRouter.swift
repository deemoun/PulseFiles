import AppKit

struct MainCommandRoutingPane: Equatable {
    var id: PaneID
    var currentDirectory: URL
    var selectedURLs: [URL]
    var focusedURL: URL?
    var focusedItemIsSymbolicLink: Bool
    var tabCount: Int

    init(id: PaneID, currentDirectory: URL, selectedURLs: [URL] = [], focusedURL: URL? = nil, focusedItemIsSymbolicLink: Bool = false, tabCount: Int = 1) {
        self.id = id
        self.currentDirectory = currentDirectory
        self.selectedURLs = selectedURLs
        self.focusedURL = focusedURL
        self.focusedItemIsSymbolicLink = focusedItemIsSymbolicLink
        self.tabCount = tabCount
    }
}

struct MainCommandRoutingState: Equatable {
    var activePaneID: PaneID
    var leftPane: MainCommandRoutingPane
    var rightPane: MainCommandRoutingPane
    var isSinglePaneMode: Bool
    var isFileOperationActive: Bool
    var sandboxAllowsSelectedURLs: Bool
    var hasUndoRecovery: Bool

    init(
        activePaneID: PaneID = .left,
        leftPane: MainCommandRoutingPane,
        rightPane: MainCommandRoutingPane,
        isSinglePaneMode: Bool = false,
        isFileOperationActive: Bool = false,
        sandboxAllowsSelectedURLs: Bool = true,
        hasUndoRecovery: Bool = false
    ) {
        self.activePaneID = activePaneID
        self.leftPane = leftPane
        self.rightPane = rightPane
        self.isSinglePaneMode = isSinglePaneMode
        self.isFileOperationActive = isFileOperationActive
        self.sandboxAllowsSelectedURLs = sandboxAllowsSelectedURLs
        self.hasUndoRecovery = hasUndoRecovery
    }

    var activePane: MainCommandRoutingPane {
        activePaneID == .left ? leftPane : rightPane
    }

    var inactivePane: MainCommandRoutingPane {
        activePaneID == .left ? rightPane : leftPane
    }
}

enum MainCommandRoutingDisabledReason: Equatable {
    case noSelection
    case noFocusedItem
    case noRealFocusedItem
    case noOppositePane
    case sandboxRejectedSelection
    case fileOperationInProgress
    case noActiveFileOperation
    case noUndoRecovery
    case focusedItemIsNotSymbolicLink
    case lastTab
}

enum MainCommandRoute: Equatable {
    case activePane(command: MainCommand, pane: PaneID, urls: [URL])
    case crossPane(command: MainCommand, sourcePane: PaneID, destinationPane: PaneID, sourceURLs: [URL], destinationDirectory: URL)
    case switchPane(to: PaneID)
    case dualPane(command: MainCommand, activePane: PaneID, oppositePane: PaneID)
    case focusedItem(command: MainCommand, pane: PaneID, url: URL)
    case symbolicLink(command: MainCommand, pane: PaneID, url: URL)
    case enabled(command: MainCommand)
    case disabled(command: MainCommand, reason: MainCommandRoutingDisabledReason)
}

struct MainCommandRouter {
    func route(_ command: MainCommand, in state: MainCommandRoutingState) -> MainCommandRoute {
        if state.isFileOperationActive, command.conflictsWithFileOperation {
            return .disabled(command: command, reason: .fileOperationInProgress)
        }
        if command == .undo { return state.hasUndoRecovery ? .enabled(command: command) : .disabled(command: command, reason: .noUndoRecovery) }
        if command == .cancelOperation {
            return state.isFileOperationActive ? .enabled(command: command) : .disabled(command: command, reason: .noActiveFileOperation)
        }

        switch command {
        case .closeTab:
            guard state.activePane.tabCount > 1 else { return .disabled(command: command, reason: .lastTab) }
            return .activePane(command: command, pane: state.activePaneID, urls: [])
        case .switchPane:
            return .switchPane(to: state.activePaneID.opposite)
        case .swapPanes, .syncOppositePane:
            guard !state.isSinglePaneMode else { return .disabled(command: command, reason: .noOppositePane) }
            return .dualPane(command: command, activePane: state.activePaneID, oppositePane: state.inactivePane.id)
        case .revealInOppositePane:
            guard !state.isSinglePaneMode else { return .disabled(command: command, reason: .noOppositePane) }
            return focusedRoute(command, in: state) {
                .focusedItem(command: command, pane: state.activePaneID, url: $0)
            }
        case .selectSameExtension, .deselectSameExtension:
            guard state.activePane.focusedURL != nil else {
                return .disabled(command: command, reason: .noRealFocusedItem)
            }
            return .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
        case .followSymbolicLink:
            guard state.activePane.focusedItemIsSymbolicLink else {
                return .disabled(command: command, reason: .focusedItemIsNotSymbolicLink)
            }
            return focusedRoute(command, in: state) {
                .symbolicLink(command: command, pane: state.activePaneID, url: $0)
            }
        case .copy, .move:
            guard !state.isSinglePaneMode else {
                return .disabled(command: command, reason: .noOppositePane)
            }
            return selectedRoute(command, in: state) {
                .crossPane(
                    command: command,
                    sourcePane: state.activePaneID,
                    destinationPane: state.inactivePane.id,
                    sourceURLs: state.activePane.selectedURLs,
                    destinationDirectory: state.inactivePane.currentDirectory
                )
            }
        case .copyToClipboard, .cutToClipboard:
            return selectedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
            }
        case .open, .viewer, .quickLook, .rename, .extractArchive, .getInfo, .reveal:
            return focusedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: [$0])
            }
        case .openWith, .trash, .duplicate, .batchRename, .createArchive:
            return selectedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
            }
        case .refresh, .toggleHiddenFiles, .sortByName, .sortByExtension, .sortByKind, .sortBySize, .sortByModified, .sortByCreated, .sortByAdded, .sortByAccessed, .sortAscending, .sortDescending, .back, .forward, .parent, .selectAll, .deselectAll, .selectByPattern, .deselectByPattern, .invertSelection, .newTab, .nextTab, .previousTab:
            return .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
        default:
            return .enabled(command: command)
        }
    }

    func commandForKeyDown(
        keyCode: UInt16,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false,
        isTextInputFocused: Bool = false
    ) -> MainCommand? {
        MainCommandShortcutRegistry.command(
            forKeyCode: keyCode,
            modifierFlags: modifierFlags(command: command, shift: shift, option: option, control: control),
            isTextInputFocused: isTextInputFocused
        )
    }

    func commandForKeyDown(_ event: NSEvent, isTextInputFocused: Bool) -> MainCommand? {
        MainCommandShortcutRegistry.command(
            forKeyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isTextInputFocused: isTextInputFocused
        )
    }

    func shouldConsumeUnmappedKeyDown(keyCode: UInt16, isTextInputFocused: Bool = false) -> Bool {
        MainCommandShortcutRegistry.shouldConsumeUnmappedKey(
            keyCode: keyCode,
            isTextInputFocused: isTextInputFocused
        )
    }

    private func modifierFlags(command: Bool, shift: Bool, option: Bool, control: Bool) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    private func selectedRoute(_ command: MainCommand, in state: MainCommandRoutingState, build: () -> MainCommandRoute) -> MainCommandRoute {
        guard !state.activePane.selectedURLs.isEmpty else {
            return .disabled(command: command, reason: .noSelection)
        }
        guard state.sandboxAllowsSelectedURLs else {
            return .disabled(command: command, reason: .sandboxRejectedSelection)
        }
        return build()
    }

    private func focusedRoute(_ command: MainCommand, in state: MainCommandRoutingState, build: (URL) -> MainCommandRoute) -> MainCommandRoute {
        guard let focusedURL = state.activePane.focusedURL else {
            return .disabled(command: command, reason: .noFocusedItem)
        }
        guard state.sandboxAllowsSelectedURLs else {
            return .disabled(command: command, reason: .sandboxRejectedSelection)
        }
        return build(focusedURL)
    }
}

enum ScratchDirectoryCommandRoute: Equatable {
    case promptForConfiguration
    case requestAccess(URL)
    case navigate(URL)
    case cancelled
}

/// Keeps scratch-location command decisions independent from AppKit prompts so
/// every non-mutating and recovery outcome can be covered by routing tests.
struct ScratchDirectoryCommandRouter {
    func route(configuredDirectory: URL?, canAccess: (URL) -> Bool) -> ScratchDirectoryCommandRoute {
        guard let configuredDirectory else { return .promptForConfiguration }
        return canAccess(configuredDirectory) ? .navigate(configuredDirectory) : .requestAccess(configuredDirectory)
    }

    func routeAfterAccessRecovery(to directory: URL, wasGranted: Bool) -> ScratchDirectoryCommandRoute {
        wasGranted ? .navigate(directory) : .cancelled
    }
}

extension MainCommand {
    var conflictsWithFileOperation: Bool {
        switch self {
        case .newFile, .newFolder, .rename, .batchRename, .createArchive, .extractArchive, .duplicate, .undo, .copy, .move, .trash, .cutToClipboard, .pasteFromClipboard:
            return true
        default:
            return false
        }
    }
}

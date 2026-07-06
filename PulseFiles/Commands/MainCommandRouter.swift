import Foundation

struct MainCommandRoutingPane: Equatable {
    var id: PaneID
    var currentDirectory: URL
    var selectedURLs: [URL]
    var focusedURL: URL?

    init(id: PaneID, currentDirectory: URL, selectedURLs: [URL] = [], focusedURL: URL? = nil) {
        self.id = id
        self.currentDirectory = currentDirectory
        self.selectedURLs = selectedURLs
        self.focusedURL = focusedURL
    }
}

struct MainCommandRoutingState: Equatable {
    var activePaneID: PaneID
    var leftPane: MainCommandRoutingPane
    var rightPane: MainCommandRoutingPane
    var isFileOperationActive: Bool
    var sandboxAllowsSelectedURLs: Bool

    init(
        activePaneID: PaneID = .left,
        leftPane: MainCommandRoutingPane,
        rightPane: MainCommandRoutingPane,
        isFileOperationActive: Bool = false,
        sandboxAllowsSelectedURLs: Bool = true
    ) {
        self.activePaneID = activePaneID
        self.leftPane = leftPane
        self.rightPane = rightPane
        self.isFileOperationActive = isFileOperationActive
        self.sandboxAllowsSelectedURLs = sandboxAllowsSelectedURLs
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
    case sandboxRejectedSelection
    case fileOperationInProgress
}

enum MainCommandRoute: Equatable {
    case activePane(command: MainCommand, pane: PaneID, urls: [URL])
    case crossPane(command: MainCommand, sourcePane: PaneID, destinationPane: PaneID, sourceURLs: [URL], destinationDirectory: URL)
    case switchPane(to: PaneID)
    case enabled(command: MainCommand)
    case disabled(command: MainCommand, reason: MainCommandRoutingDisabledReason)
}

struct MainCommandRouter {
    func route(_ command: MainCommand, in state: MainCommandRoutingState) -> MainCommandRoute {
        if state.isFileOperationActive, command.conflictsWithFileOperation {
            return .disabled(command: command, reason: .fileOperationInProgress)
        }

        switch command {
        case .switchPane:
            return .switchPane(to: state.activePaneID.opposite)
        case .focusLeftPane:
            return .switchPane(to: .left)
        case .focusRightPane:
            return .switchPane(to: .right)
        case .copy, .move:
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
        case .quickLook:
            return focusedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: [$0])
            }
        case .open, .rename, .trash, .reveal:
            return selectedRoute(command, in: state) {
                .activePane(command: command, pane: state.activePaneID, urls: state.activePane.selectedURLs)
            }
        case .refresh, .toggleHiddenFiles, .sortByName, .sortBySize, .sortByModified, .sortAscending, .sortDescending, .back, .forward, .parent:
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
        if command && keyCode == 48 { return nil }
        if isTextInputFocused, !(command && keyCode == 50) { return nil }
        let plain = !command && !shift && !option && !control
        let shiftOnly = shift && !command && !option && !control

        if command && !shift && !option && !control && keyCode == 8 { return .copyToClipboard }
        if command && !shift && !option && !control && keyCode == 7 { return .cutToClipboard }
        if command && !shift && !option && !control && keyCode == 9 { return .pasteFromClipboard }
        if command && !shift && !option && !control && keyCode == 50 { return .toggleTerminal }
        if command && !shift && !option && !control && keyCode == 17 { return .togglePaneLayout }
        if plain && keyCode == 49 { return .quickLook }
        if plain && keyCode == 48 { return .switchPane }
        if shiftOnly && keyCode == 98 { return .newFile }
        if plain && keyCode == 98 { return .newFolder }
        if plain && keyCode == 120 { return .rename }
        if plain && keyCode == 96 { return .copy }
        if plain && keyCode == 97 { return .move }
        if plain && keyCode == 100 { return .trash }
        if command && !shift && !option && !control && keyCode == 15 { return .refresh }
        if command && shift && !option && !control && keyCode == 123 { return .focusLeftPane }
        if command && shift && !option && !control && keyCode == 124 { return .focusRightPane }
        if command && option && !shift && !control && keyCode == 37 { return .downloads }
        return nil
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

extension MainCommand {
    var conflictsWithFileOperation: Bool {
        switch self {
        case .newFile, .newFolder, .rename, .copy, .move, .trash, .cutToClipboard, .pasteFromClipboard:
            return true
        default:
            return false
        }
    }
}

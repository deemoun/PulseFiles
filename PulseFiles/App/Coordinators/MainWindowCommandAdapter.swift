// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesAppCoordination
import PulseFilesModels
import PulseFilesUtilities
import PulseFilesWorkflows

/// Thin AppKit boundary for menu forwarding and state decoration. Command
/// execution is always delegated to `MainCommandHandling`.
@MainActor
final class MainWindowCommandAdapter: NSObject {
    struct ValidationState {
        let isEnabled: (MainCommand) -> Bool
        let undoTitle: String?
        let sidebarVisible: Bool
        let terminalVisible: Bool
        let singlePane: Bool
        let showsHiddenFiles: Bool
        let permanentlyDeletes: Bool
        let sort: FileSortDescriptor
    }

    private weak var handler: (any MainCommandHandling)?

    init(handler: any MainCommandHandling) { self.handler = handler }

    func forward(_ route: MainCommandRoute) { handler?.handle(route) }

    func validate(_ item: NSMenuItem, command: MainCommand?, state: ValidationState, actions: Actions) -> Bool {
        let enabled = command.map(state.isEnabled) ?? true
        switch item.action {
        case actions.undo: item.title = state.undoTitle?.localized ?? "Undo".localized
        case actions.sidebar: item.state = state.sidebarVisible ? .on : .off
        case actions.terminal: item.state = state.terminalVisible ? .on : .off
        case actions.paneLayout:
            item.title = state.singlePane ? "Use Dual Pane".localized : "Use Single Pane".localized
            item.state = state.singlePane ? .on : .off
        case actions.hiddenFiles: item.state = state.showsHiddenFiles ? .on : .off
        case actions.trash: item.title = state.permanentlyDeletes ? "Permanently Delete".localized : "Move to Trash".localized
        case actions.sortName: item.state = state.sort.key == .name ? .on : .off
        case actions.sortExtension: item.state = state.sort.key == .extension ? .on : .off
        case actions.sortKind: item.state = state.sort.key == .kind ? .on : .off
        case actions.sortSize: item.state = state.sort.key == .size ? .on : .off
        case actions.sortModified: item.state = state.sort.key == .modified ? .on : .off
        case actions.sortCreated: item.state = state.sort.key == .created ? .on : .off
        case actions.sortAdded: item.state = state.sort.key == .added ? .on : .off
        case actions.sortAccessed: item.state = state.sort.key == .accessed ? .on : .off
        case actions.sortAscending: item.state = state.sort.ascending ? .on : .off
        case actions.sortDescending: item.state = state.sort.ascending ? .off : .on
        default: item.state = .off
        }
        return enabled
    }

    struct Actions {
        let undo, sidebar, terminal, paneLayout, hiddenFiles, trash: Selector
        let sortName, sortExtension, sortKind, sortSize, sortModified, sortCreated, sortAdded, sortAccessed: Selector
        let sortAscending, sortDescending: Selector
    }
}

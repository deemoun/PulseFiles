// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// AppKit-free owner of the logical, per-tab navigation state.
package struct PaneNavigationStateMachine {
    package struct HistoryTransition {
        package let prior: NavigationHistory
        package let destination: NavigationHistory
        package let directory: URL
    }

    package var state: PaneState

    package init(state: PaneState) { self.state = state }

    package mutating func restore(_ restored: PaneState) {
        state = restored
        state.currentDirectory = restored.currentDirectory.standardizedFileURL
    }

    package mutating func activateTab(id: UUID, savingSearchQuery query: String) -> Bool {
        guard id != state.activeTabID, state.tabs.contains(where: { $0.id == id }) else { return false }
        state.searchQuery = query
        state.activeTabID = id
        return true
    }

    package mutating func closeTab(id: UUID?) -> Bool {
        guard state.tabs.count > 1,
              let index = state.tabs.firstIndex(where: { $0.id == (id ?? state.activeTabID) }) else { return false }
        let wasActive = state.tabs[index].id == state.activeTabID
        state.tabs.remove(at: index)
        if wasActive { state.activeTabID = state.tabs[min(index, state.tabs.count - 1)].id }
        return wasActive
    }

    package func backTransition() -> HistoryTransition? {
        var destination = state.history
        guard let directory = destination.goBack() else { return nil }
        return HistoryTransition(prior: state.history, destination: destination, directory: directory)
    }

    package func forwardTransition() -> HistoryTransition? {
        var destination = state.history
        guard let directory = destination.goForward() else { return nil }
        return HistoryTransition(prior: state.history, destination: destination, directory: directory)
    }

    package mutating func commitDirectory(_ directory: URL, addToHistory: Bool, transition: HistoryTransition?) {
        let previous = state.currentDirectory
        state.currentDirectory = directory
        if let transition { state.history = transition.destination }
        else if addToHistory, directory != previous { state.history.visit(directory) }
    }

    package mutating func rollBack(_ transition: HistoryTransition?) {
        if let transition { state.history = transition.prior }
    }
}

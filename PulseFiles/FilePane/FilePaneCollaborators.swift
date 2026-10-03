// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesModels
import PulseFilesWorkflows

package enum FilePaneNavigationEvent {
    case activate, switchPane
    case open(URL)
    case directoryChanged(URL)
    case directoryAccessGranted(URL)
}

package enum FilePaneCommandEvent {
    case command(MainCommand)
    case toggleTerminal, newFolder, newFile
    case openWith(URL, URL?)
    case drop([URL], destination: URL, copy: Bool)
    case rename(FileItem, String)
}

package enum FilePanePresentationEvent {
    case displayPreferences(Bool, FileSortDescriptor)
    case selection([FileItem])
    case searchQuery(String)
    case tabs(PaneState)
    case mode(PanePresentationMode)
}

package protocol FilePaneNavigationDelegate: AnyObject {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePaneNavigationEvent)
}

package protocol FilePaneCommandDelegate: AnyObject {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePaneCommandEvent)
}

package protocol FilePanePresentationDelegate: AnyObject {
    func filePane(_ pane: FilePaneViewController, didEmit event: FilePanePresentationEvent)
}

/// Owns selection/focus restoration and exposes only renderable snapshots.
package final class PaneSelectionRestorationCoordinator {
    package struct Snapshot { let pendingURL: URL?; let previousURLs: [URL] }
    private var state = PaneSelectionRestorationState()

    package var snapshot: Snapshot { .init(pendingURL: state.pendingURL, previousURLs: state.previousURLs) }
    package func prepare(_ url: URL?) { state.prepare(url) }
    package func reset() { state.reset() }
    package func record(_ urls: [URL]) { state.record(urls) }
    package func consumePending(in urls: [URL], normalize: (URL) -> String) -> URL? {
        state.consumePending(ifAvailable: urls, normalize: normalize)
    }
    package func rows(in urls: [URL], offset: Int, normalize: (URL) -> String) -> IndexSet {
        IndexSet(state.indexes(in: urls, normalize: normalize).map { $0 + offset })
    }
}

/// Owns quick-search keystroke interpretation and transient presentation state.
package final class QuickSearchCoordinator {
    package enum Command: Equatable { case update(String), navigateParent, ignored }
    private var state = PaneQuickSearchState()
    package var focusedURLBeforeSearch: URL? { state.focusedURLBeforeSearch }
    package func transition(from old: String, to new: String, focusedURL: URL?) { state.transition(from: old, to: new, focusedURL: focusedURL) }
    package func command(keyCode: UInt16, input: String?, modifiersAreEmpty: Bool, query: String) -> Command {
        if keyCode == 53, !query.isEmpty { return .update("") }
        if keyCode == 51, modifiersAreEmpty { return query.isEmpty ? .navigateParent : .update(String(query.dropLast())) }
        guard modifiersAreEmpty, let input, !input.isEmpty,
              input.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) else { return .ignored }
        return .update(query + input)
    }
}

/// Owns table reload coalescing while inline rename metadata is unresolved.
package final class TableReloadCoordinator {
    package enum Request { case reloadNow, probe(URL), deferred }
    private var deferred = false
    private var probingURL: URL?
    package var hasDeferredReload: Bool { deferred }
    package func request(editedURL: URL?, isEditing: Bool, cachedExists: Bool?) -> Request {
        guard isEditing, let editedURL else { deferred = false; probingURL = nil; return .reloadNow }
        guard let cachedExists else {
            deferred = true
            if probingURL == editedURL { return .deferred }
            probingURL = editedURL
            return .probe(editedURL)
        }
        probingURL = nil
        if cachedExists { deferred = true; return .deferred }
        deferred = false; return .reloadNow
    }
    package func clearDeferred() -> Bool { defer { deferred = false }; return deferred }
}

/// Renders tabs and presentation mode without owning pane navigation state.
package final class PaneChromeCoordinator {
    package struct Input { let tabs: [PaneTabState]; let activeTabID: UUID; let mode: PanePresentationMode }
    private let tabs: NSSegmentedControl
    private let modes: NSSegmentedControl
    package init(tabs: NSSegmentedControl, modes: NSSegmentedControl) { self.tabs = tabs; self.modes = modes }
    package func render(_ input: Input) {
        tabs.segmentCount = input.tabs.count
        for (index, tab) in input.tabs.enumerated() {
            let title = tab.currentDirectory.lastPathComponent.isEmpty ? "/" : tab.currentDirectory.lastPathComponent
            tabs.setLabel(title, forSegment: index)
            tabs.setToolTip(tab.currentDirectory.path, forSegment: index)
        }
        tabs.selectedSegment = input.tabs.firstIndex { $0.id == input.activeTabID } ?? 0
        modes.selectedSegment = PanePresentationMode.allCases.firstIndex(of: input.mode) ?? 0
    }
}

/// Maps directory-loading state to the content overlay's AppKit presentation.
package final class ContentOverlayCoordinator {
    package struct Input {
        let paneID: PaneID; let isLoading: Bool; let visibleItems: [FileItem]
        let errorMessage: String?; let actions: [PaneStatusView.Action]
    }
    private let view: PaneContentOverlayView
    package init(view: PaneContentOverlayView) { self.view = view }
    package func render(_ input: Input) {
        view.configure(paneID: input.paneID, isLoading: input.isLoading, visibleItems: input.visibleItems,
                       errorMessage: input.errorMessage, actions: input.actions)
    }
}

@MainActor
package final class ThumbnailRequestCoordinator {
    private var tasks: [URL: Task<Void, Never>] = [:]

    package func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    package func request(for url: URL, operation: @escaping @MainActor () async -> Void) {
        tasks[url]?.cancel()
        tasks[url] = Task { [weak self] in
            await operation()
            guard !Task.isCancelled else { return }
            self?.tasks[url] = nil
        }
    }
}

import AppKit

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

/// Owns the transient focus captured while the view model applies a quick-search filter.
package struct QuickSearchState {
    private(set) var focusedURLBeforeSearch: URL?

    mutating func transition(from oldQuery: String, to newQuery: String, focusedURL: URL?) {
        if oldQuery.isEmpty, !newQuery.isEmpty { focusedURLBeforeSearch = focusedURL }
        if newQuery.isEmpty { focusedURLBeforeSearch = nil }
    }
}

/// URL-based selection state that remains stable across sorting and table reloads.
package struct FilePaneSelectionRestoration {
    private(set) var pendingURL: URL?
    private(set) var previousURLs: [URL] = []

    mutating func prepare(_ url: URL?) { pendingURL = url }
    mutating func clear() { pendingURL = nil; previousURLs = [] }
    mutating func record(_ urls: [URL]) { previousURLs = urls }
    mutating func consumePending() -> URL? { defer { pendingURL = nil }; return pendingURL }

    package func rows(in urls: [URL], offset: Int, normalize: (URL) -> String) -> IndexSet {
        let paths = Set(previousURLs.map(normalize))
        return IndexSet(urls.enumerated().compactMap { paths.contains(normalize($0.element)) ? $0.offset + offset : nil })
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

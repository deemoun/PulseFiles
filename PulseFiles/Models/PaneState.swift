import Foundation

enum PaneID: Equatable {
    case left
    case right

    var opposite: PaneID {
        self == .left ? .right : .left
    }
}

enum FileSortKey: String, Codable, Hashable {
    case name
    case kind
    case size
    case modified
}

struct FileSortDescriptor: Codable, Equatable, Hashable {
    var key: FileSortKey = .name
    var ascending: Bool = true
}

struct PaneState {
    var currentDirectory: URL
    /// The marked set used by copy, move, trash, drag, and other bulk operations.
    /// Focus is deliberately represented separately by `focusedURL`.
    var markedURLs: Set<URL> = []
    var focusedRow: Int = 0
    var focusedURL: URL?
    var searchQuery = ""
    var history = NavigationHistory()
    var sort = FileSortDescriptor()
    var showsHiddenFiles = false

    init(
        currentDirectory: URL,
        markedURLs: Set<URL> = [],
        focusedRow: Int = 0,
        focusedURL: URL? = nil,
        searchQuery: String = "",
        history: NavigationHistory = NavigationHistory(),
        sort: FileSortDescriptor = FileSortDescriptor(),
        showsHiddenFiles: Bool = false
    ) {
        self.currentDirectory = currentDirectory
        self.markedURLs = markedURLs
        self.focusedRow = focusedRow
        self.focusedURL = focusedURL
        self.searchQuery = searchQuery
        self.history = history
        self.sort = sort
        self.showsHiddenFiles = showsHiddenFiles
    }

    @available(*, deprecated, message: "Use markedURLs; selection means the operation mark set, not keyboard focus.")
    init(
        currentDirectory: URL,
        selectedURLs: Set<URL>,
        focusedRow: Int = 0,
        focusedURL: URL? = nil,
        searchQuery: String = "",
        history: NavigationHistory = NavigationHistory(),
        sort: FileSortDescriptor = FileSortDescriptor(),
        showsHiddenFiles: Bool = false
    ) {
        self.init(currentDirectory: currentDirectory, markedURLs: selectedURLs, focusedRow: focusedRow, focusedURL: focusedURL, searchQuery: searchQuery, history: history, sort: sort, showsHiddenFiles: showsHiddenFiles)
    }

    /// Source-compatible spelling for older callers. PaneState is not persisted,
    /// but retaining this alias also avoids changing any external state adapters.
    @available(*, deprecated, renamed: "markedURLs")
    var selectedURLs: Set<URL> {
        get { markedURLs }
        set { markedURLs = newValue }
    }

    mutating func setFocus(_ url: URL?) {
        focusedURL = url
    }
}

/// Row-independent focus navigation shared by keyboard and accessibility tests.
/// A missing/filtered focus is retained in pane state and reappears when its URL
/// becomes visible again; movement starts at the nearest list boundary.
enum PaneFocusNavigation {
    static func destination(currentURL: URL?, visibleURLs: [URL], delta: Int) -> URL? {
        guard !visibleURLs.isEmpty, delta != 0 else { return currentURL }
        let currentIndex = currentURL.flatMap { current in
            visibleURLs.firstIndex { $0.standardizedFileURL == current.standardizedFileURL }
        }
        let startingIndex = currentIndex ?? (delta > 0 ? -1 : visibleURLs.count)
        let destinationIndex = min(max(startingIndex + delta, 0), visibleURLs.count - 1)
        return visibleURLs[destinationIndex]
    }
}

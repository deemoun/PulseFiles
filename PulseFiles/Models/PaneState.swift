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
    case `extension`
    case kind
    case size
    case modified
    case created
    case added
    case accessed
}

enum FileSortComparisonMode: String, Codable, Hashable {
    case naturalLocalized
    case caseInsensitive
    case caseSensitive
}

struct FileSortDescriptor: Codable, Equatable, Hashable {
    var key: FileSortKey = .name
    var ascending: Bool = true
    var comparisonMode: FileSortComparisonMode = .naturalLocalized
    var foldersFirst: Bool = true

    init(
        key: FileSortKey = .name,
        ascending: Bool = true,
        comparisonMode: FileSortComparisonMode = .naturalLocalized,
        foldersFirst: Bool = true
    ) {
        self.key = key
        self.ascending = ascending
        self.comparisonMode = comparisonMode
        self.foldersFirst = foldersFirst
    }

    private enum CodingKeys: String, CodingKey { case key, ascending, comparisonMode, foldersFirst }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decodeIfPresent(FileSortKey.self, forKey: .key) ?? .name
        ascending = try values.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        comparisonMode = try values.decodeIfPresent(FileSortComparisonMode.self, forKey: .comparisonMode) ?? .naturalLocalized
        foldersFirst = try values.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
    }
}

struct PaneTabState: Identifiable, Equatable {
    let id: UUID
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
        id: UUID = UUID(),
        currentDirectory: URL,
        markedURLs: Set<URL> = [],
        focusedRow: Int = 0,
        focusedURL: URL? = nil,
        searchQuery: String = "",
        history: NavigationHistory = NavigationHistory(),
        sort: FileSortDescriptor = FileSortDescriptor(),
        showsHiddenFiles: Bool = false
    ) {
        self.id = id
        self.currentDirectory = currentDirectory
        self.markedURLs = markedURLs
        self.focusedRow = focusedRow
        self.focusedURL = focusedURL
        self.searchQuery = searchQuery
        self.history = history
        self.sort = sort
        self.showsHiddenFiles = showsHiddenFiles
    }

    mutating func setFocus(_ url: URL?) { focusedURL = url }
}

struct PaneState: Equatable {
    var tabs: [PaneTabState]
    var activeTabID: UUID

    var activeTabIndex: Int { tabs.firstIndex { $0.id == activeTabID } ?? 0 }
    var currentDirectory: URL { get { tabs[activeTabIndex].currentDirectory } set { tabs[activeTabIndex].currentDirectory = newValue } }
    var markedURLs: Set<URL> { get { tabs[activeTabIndex].markedURLs } set { tabs[activeTabIndex].markedURLs = newValue } }
    var focusedRow: Int { get { tabs[activeTabIndex].focusedRow } set { tabs[activeTabIndex].focusedRow = newValue } }
    var focusedURL: URL? { get { tabs[activeTabIndex].focusedURL } set { tabs[activeTabIndex].focusedURL = newValue } }
    var searchQuery: String { get { tabs[activeTabIndex].searchQuery } set { tabs[activeTabIndex].searchQuery = newValue } }
    var history: NavigationHistory { get { tabs[activeTabIndex].history } set { tabs[activeTabIndex].history = newValue } }
    var sort: FileSortDescriptor { get { tabs[activeTabIndex].sort } set { tabs[activeTabIndex].sort = newValue } }
    var showsHiddenFiles: Bool { get { tabs[activeTabIndex].showsHiddenFiles } set { tabs[activeTabIndex].showsHiddenFiles = newValue } }

    init(tabs: [PaneTabState], activeTabID: UUID? = nil) {
        precondition(!tabs.isEmpty, "A pane must contain at least one tab.")
        self.tabs = tabs
        self.activeTabID = activeTabID.flatMap { id in tabs.contains { $0.id == id } ? id : nil } ?? tabs[0].id
    }

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
        let tab = PaneTabState(currentDirectory: currentDirectory, markedURLs: markedURLs, focusedRow: focusedRow, focusedURL: focusedURL, searchQuery: searchQuery, history: history, sort: sort, showsHiddenFiles: showsHiddenFiles)
        self.init(tabs: [tab], activeTabID: tab.id)
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

    mutating func setFocus(_ url: URL?) { focusedURL = url }
}

/// Deliberately excludes history, search, focus and marks: those are ephemeral and
/// can refer to stale or sensitive filesystem objects after relaunch.
struct PaneTabRestorationState: Codable, Equatable {
    var id: UUID
    var directory: URL
    var sort: FileSortDescriptor
    var showsHiddenFiles: Bool
}

struct PaneRestorationState: Codable, Equatable {
    var tabs: [PaneTabRestorationState]
    var activeTabID: UUID?

    init(tabs: [PaneTabRestorationState], activeTabID: UUID?) {
        self.tabs = tabs
        self.activeTabID = activeTabID
    }

    init(paneState: PaneState) {
        tabs = paneState.tabs.map { .init(id: $0.id, directory: $0.currentDirectory, sort: $0.sort, showsHiddenFiles: $0.showsHiddenFiles) }
        activeTabID = paneState.activeTabID
    }
}

enum PaneFocusDestination: Equatable {
    case parent
    case item(URL)
}

/// Row-independent focus navigation shared by keyboard and accessibility tests.
/// A missing/filtered focus is retained in pane state and reappears when its URL
/// becomes visible again; movement starts at the nearest list boundary.
enum PaneFocusNavigation {
    static func destination(current: PaneFocusDestination?, displayed: [PaneFocusDestination], delta: Int) -> PaneFocusDestination? {
        guard !displayed.isEmpty, delta != 0 else { return current }
        let currentIndex = current.flatMap { current in
            displayed.firstIndex { destinationsMatch($0, current) }
        }
        let startingIndex = currentIndex ?? (delta > 0 ? -1 : displayed.count)
        let destinationIndex = min(max(startingIndex + delta, 0), displayed.count - 1)
        return displayed[destinationIndex]
    }

    private static func destinationsMatch(_ lhs: PaneFocusDestination, _ rhs: PaneFocusDestination) -> Bool {
        switch (lhs, rhs) {
        case (.parent, .parent): return true
        case let (.item(lhsURL), .item(rhsURL)): return lhsURL.standardizedFileURL == rhsURL.standardizedFileURL
        default: return false
        }
    }
}

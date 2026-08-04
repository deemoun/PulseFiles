import Foundation
import PulseFilesUtilities

package enum PaneID: Equatable {
    case left
    case right

    package var opposite: PaneID {
        self == .left ? .right : .left
    }
}

package enum FileSortKey: String, Codable, Hashable {
    case name
    case `extension`
    case kind
    case size
    case modified
    case created
    case added
    case accessed
}

package enum FileSortComparisonMode: String, Codable, Hashable {
    case naturalLocalized
    case caseInsensitive
    case caseSensitive
}

package struct FileSortDescriptor: Codable, Equatable, Hashable {
    package var key: FileSortKey = .name
    package var ascending: Bool = true
    package var comparisonMode: FileSortComparisonMode = .naturalLocalized
    package var foldersFirst: Bool = true

    package init(
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

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decodeIfPresent(FileSortKey.self, forKey: .key) ?? .name
        ascending = try values.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        comparisonMode = try values.decodeIfPresent(FileSortComparisonMode.self, forKey: .comparisonMode) ?? .naturalLocalized
        foldersFirst = try values.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
    }
}

package struct PaneTabState: Identifiable, Equatable {
    package let id: UUID
    package var currentDirectory: URL
    /// The marked set used by copy, move, trash, drag, and other bulk operations.
    /// Focus is deliberately represented separately by `focusedURL`.
    package var markedURLs: Set<URL> = []
    package var focusedRow: Int = 0
    package var focusedURL: URL?
    package var searchQuery = ""
    package var history = NavigationHistory()
    package var sort = FileSortDescriptor()
    package var showsHiddenFiles = false

    package init(
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

    package mutating func setFocus(_ url: URL?) { focusedURL = url }
}

package struct PaneState: Equatable {
    package var tabs: [PaneTabState]
    package var activeTabID: UUID

    package var activeTabIndex: Int { tabs.firstIndex { $0.id == activeTabID } ?? 0 }
    package var currentDirectory: URL { get { tabs[activeTabIndex].currentDirectory } set { tabs[activeTabIndex].currentDirectory = newValue } }
    package var markedURLs: Set<URL> { get { tabs[activeTabIndex].markedURLs } set { tabs[activeTabIndex].markedURLs = newValue } }
    package var focusedRow: Int { get { tabs[activeTabIndex].focusedRow } set { tabs[activeTabIndex].focusedRow = newValue } }
    package var focusedURL: URL? { get { tabs[activeTabIndex].focusedURL } set { tabs[activeTabIndex].focusedURL = newValue } }
    package var searchQuery: String { get { tabs[activeTabIndex].searchQuery } set { tabs[activeTabIndex].searchQuery = newValue } }
    package var history: NavigationHistory { get { tabs[activeTabIndex].history } set { tabs[activeTabIndex].history = newValue } }
    package var sort: FileSortDescriptor { get { tabs[activeTabIndex].sort } set { tabs[activeTabIndex].sort = newValue } }
    package var showsHiddenFiles: Bool { get { tabs[activeTabIndex].showsHiddenFiles } set { tabs[activeTabIndex].showsHiddenFiles = newValue } }

    package init(tabs: [PaneTabState], activeTabID: UUID? = nil) {
        precondition(!tabs.isEmpty, "A pane must contain at least one tab.")
        self.tabs = tabs
        self.activeTabID = activeTabID.flatMap { id in tabs.contains { $0.id == id } ? id : nil } ?? tabs[0].id
    }

    package init(
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
    package init(
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
    package var selectedURLs: Set<URL> {
        get { markedURLs }
        set { markedURLs = newValue }
    }

    package mutating func setFocus(_ url: URL?) { focusedURL = url }
}

/// Deliberately excludes history, search, focus and marks: those are ephemeral and
/// can refer to stale or sensitive filesystem objects after relaunch.
package struct PaneTabRestorationState: Codable, Equatable {
    package var id: UUID
    package var directory: URL
    package var sort: FileSortDescriptor
    package var showsHiddenFiles: Bool
}

package struct PaneRestorationState: Codable, Equatable {
    package var tabs: [PaneTabRestorationState]
    package var activeTabID: UUID?

    package init(tabs: [PaneTabRestorationState], activeTabID: UUID?) {
        self.tabs = tabs
        self.activeTabID = activeTabID
    }

    package init(paneState: PaneState) {
        tabs = paneState.tabs.map { .init(id: $0.id, directory: $0.currentDirectory, sort: $0.sort, showsHiddenFiles: $0.showsHiddenFiles) }
        activeTabID = paneState.activeTabID
    }
}

package enum PaneFocusDestination: Equatable {
    case parent
    case item(URL)
}

/// Row-independent focus navigation shared by keyboard and accessibility tests.
/// A missing/filtered focus is retained in pane state and reappears when its URL
/// becomes visible again; movement starts at the nearest list boundary.
package enum PaneFocusNavigation {
    package static func destination(current: PaneFocusDestination?, displayed: [PaneFocusDestination], delta: Int) -> PaneFocusDestination? {
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

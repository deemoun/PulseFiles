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

struct PaneState: Equatable {
    var currentDirectory: URL
    var selectedURLs: Set<URL> = []
    var focusedRow: Int = 0
    var focusedURL: URL?
    var searchQuery = ""
    var history = NavigationHistory()
    var sort = FileSortDescriptor()
    var showsHiddenFiles = false

    init(
        currentDirectory: URL,
        selectedURLs: Set<URL> = [],
        focusedRow: Int = 0,
        focusedURL: URL? = nil,
        searchQuery: String = "",
        history: NavigationHistory = NavigationHistory(),
        sort: FileSortDescriptor = FileSortDescriptor(),
        showsHiddenFiles: Bool = false
    ) {
        self.currentDirectory = currentDirectory
        self.selectedURLs = selectedURLs
        self.focusedRow = focusedRow
        self.focusedURL = focusedURL
        self.searchQuery = searchQuery
        self.history = history
        self.sort = sort
        self.showsHiddenFiles = showsHiddenFiles
    }
}

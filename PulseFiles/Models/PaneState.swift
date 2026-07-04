import Foundation

enum PaneID {
    case left
    case right

    var opposite: PaneID {
        self == .left ? .right : .left
    }
}

enum FileSortKey: String, Codable {
    case name
    case size
    case modified
}

struct FileSortDescriptor: Codable, Equatable {
    var key: FileSortKey = .name
    var ascending: Bool = true
}

struct PaneState {
    var currentDirectory: URL
    var selectedURLs: Set<URL> = []
    var focusedRow: Int = 0
    var history = NavigationHistory()
    var sort = FileSortDescriptor()
    var showsHiddenFiles = false
}

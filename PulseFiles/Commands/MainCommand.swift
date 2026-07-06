import Foundation

enum MainCommand: Equatable {
    case open
    case quickLook
    case newFile
    case newFolder
    case rename
    case copy
    case move
    case copyToClipboard
    case cutToClipboard
    case pasteFromClipboard
    case trash
    case refresh
    case reveal
    case toggleHiddenFiles
    case sortByName
    case sortBySize
    case sortByModified
    case sortAscending
    case sortDescending
    case toggleTerminal
    case toggleSidebar
    case togglePaneLayout
    case back
    case forward
    case parent
    case goToFolder
    case home
    case downloads
    case applications
    case switchPane
    case focusLeftPane
    case focusRightPane

    init(commandBarAction: CommandBarAction) {
        switch commandBarAction {
        case .newFile: self = .newFile
        case .newFolder: self = .newFolder
        case .rename: self = .rename
        case .copy: self = .copy
        case .move: self = .move
        case .delete: self = .trash
        case .view, .edit: self = .open
        }
    }
}

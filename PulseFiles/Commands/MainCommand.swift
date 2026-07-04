import Foundation

enum MainCommand {
    case open
    case newFile
    case newFolder
    case rename
    case copy
    case move
    case trash
    case refresh
    case toggleTerminal
    case toggleSidebar
    case back
    case forward
    case parent
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

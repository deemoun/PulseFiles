import Foundation

enum CommandBarAction: String, CaseIterable {
    case open = "Open"
    case newFile = "New File"
    case newFolder = "New Folder"
    case rename = "Rename"
    case view = "View"
    case edit = "Edit"
    case copy = "Copy"
    case move = "Move"
    case delete = "Delete"
    case more = "More"

    var shortcut: String {
        switch self {
        case .open: return "Return"
        case .newFile: return "Shift F7"
        case .newFolder: return "F7"
        case .rename: return "F2"
        case .view: return "F3"
        case .edit: return "F4"
        case .copy: return "F5"
        case .move: return "F6"
        case .delete: return "F8"
        case .more: return "..."
        }
    }
}

import Foundation

enum CommandBarAction: String, CaseIterable {
    case rename = "Rename"
    case view = "View"
    case copy = "Copy"
    case move = "Move"
    case newFolder = "New Folder"
    case newFile = "New File"
    case delete = "Delete"
    case cancelOperation = "Cancel Operation"
    case newTab = "New Tab"
    case closeTab = "Close Tab"
    case nextTab = "Next Tab"
    case previousTab = "Previous Tab"

    var title: String {
        switch self {
        case .rename: return "Rename".localized
        case .view: return "View".localized
        case .copy: return "Copy".localized
        case .move: return "Move".localized
        case .newFolder: return "New Folder".localized
        case .newFile: return "New File".localized
        case .delete: return "Delete".localized
        case .cancelOperation: return "Cancel Operation".localized
        case .newTab: return "New Tab".localized
        case .closeTab: return "Close Tab".localized
        case .nextTab: return "Next Tab".localized
        case .previousTab: return "Previous Tab".localized
        }
    }

    var shortcut: String {
        MainCommandShortcutRegistry.shortcut(for: MainCommand(commandBarAction: self)).displayLabel
    }
}

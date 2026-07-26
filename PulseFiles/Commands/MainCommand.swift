import Foundation

enum MainCommand: CaseIterable, Equatable {
    case open
    case openWith
    case quickLook
    case newFile
    case newFolder
    case rename
    case duplicate
    case getInfo
    case selectAll
    case invertSelection
    case undo
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
    case sortByKind
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
    case searchDescendants
    case home
    case downloads
    case applications
    case scratchDirectory
    /// Exchanges the complete logical state of both panes without changing which physical pane is active.
    case swapPanes
    /// Opens the active pane directory in the opposite pane.
    case syncOppositePane
    /// Opens the focused item’s parent and selects it in the opposite pane.
    case revealInOppositePane
    /// Resolves exactly one symbolic-link hop and opens or selects its target.
    case followSymbolicLink
    case switchPane
    case cancelOperation
    case debugLogs
    case exportDiagnostics

    init(commandBarAction: CommandBarAction) {
        switch commandBarAction {
        case .newFile: self = .newFile
        case .newFolder: self = .newFolder
        case .rename: self = .rename
        case .copy: self = .copy
        case .move: self = .move
        case .delete: self = .trash
        case .cancelOperation: self = .cancelOperation
        case .view: self = .open
        }
    }
}

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
    case deselectAll
    case selectByPattern
    case deselectByPattern
    case selectSameExtension
    case deselectSameExtension
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
    case sortByExtension
    case sortByKind
    case sortBySize
    case sortByModified
    case sortByCreated
    case sortByAdded
    case sortByAccessed
    case sortAscending
    case sortDescending
    case toggleTerminal
    case toggleSidebar
    case togglePaneLayout
    case back
    case forward
    case parent
    case goToFolder
    case quickLocations
    case searchDescendants
    case home
    case downloads
    case applications
    case scratchDirectory
    case switchPane
    case swapPanes
    case syncOppositePane
    case revealInOppositePane
    case followSymbolicLink
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

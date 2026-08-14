import Foundation

enum AccessibilityIdentifiers {
    enum Pane {
        static let left = "pulsefiles.pane.left"
        static let right = "pulsefiles.pane.right"
        static let leftActiveIndicator = "pulsefiles.pane.left.activeIndicator"
        static let rightActiveIndicator = "pulsefiles.pane.right.activeIndicator"
        static let leftTable = "pulsefiles.pane.left.table"
        static let rightTable = "pulsefiles.pane.right.table"
        static let leftBreadcrumb = "pulsefiles.pane.left.breadcrumb"
        static let rightBreadcrumb = "pulsefiles.pane.right.breadcrumb"
        static let leftContentOverlay = "pulsefiles.pane.left.contentOverlay"
        static let rightContentOverlay = "pulsefiles.pane.right.contentOverlay"
        static let leftContentOverlayTitle = "pulsefiles.pane.left.contentOverlay.title"
        static let rightContentOverlayTitle = "pulsefiles.pane.right.contentOverlay.title"
        static let leftLoadingIndicator = "pulsefiles.pane.left.contentOverlay.loadingIndicator"
        static let rightLoadingIndicator = "pulsefiles.pane.right.contentOverlay.loadingIndicator"

        static func container(for paneID: PaneID) -> String {
            paneID == .left ? left : right
        }

        static func activeIndicator(for paneID: PaneID) -> String {
            paneID == .left ? leftActiveIndicator : rightActiveIndicator
        }

        static func table(for paneID: PaneID) -> String {
            paneID == .left ? leftTable : rightTable
        }

        static func breadcrumb(for paneID: PaneID) -> String {
            paneID == .left ? leftBreadcrumb : rightBreadcrumb
        }

        static func contentOverlay(for paneID: PaneID) -> String {
            paneID == .left ? leftContentOverlay : rightContentOverlay
        }

        static func contentOverlayTitle(for paneID: PaneID) -> String {
            paneID == .left ? leftContentOverlayTitle : rightContentOverlayTitle
        }

        static func loadingIndicator(for paneID: PaneID) -> String {
            paneID == .left ? leftLoadingIndicator : rightLoadingIndicator
        }

        static func contentOverlayAction(for paneID: PaneID, index: Int) -> String {
            "\(contentOverlay(for: paneID)).action.\(index)"
        }
    }

    enum Toolbar {
        static let searchField = "pulsefiles.toolbar.searchField"
        static let sidebarToggle = "pulsefiles.toolbar.sidebarToggle"
        static let terminalToggle = "pulsefiles.toolbar.terminalToggle"
    }

    enum Sidebar {
        static let panel = "pulsefiles.sidebar.panel"
        static let list = "pulsefiles.sidebar.list"
        static let scratchFolder = "pulsefiles.sidebar.scratchFolder"
    }

    enum Settings {
        static let categoryControl = "pulsefiles.settings.categories"
        static let pageHost = "pulsefiles.settings.pageHost"
        static let done = "pulsefiles.settings.done"
        static let languageSelector = "pulsefiles.settings.language.selector"
        static let confirmCopy = "pulsefiles.settings.operations.confirmCopy"
        static let confirmMove = "pulsefiles.settings.operations.confirmMove"
        static let confirmDelete = "pulsefiles.settings.operations.confirmDelete"
        static let permanentDelete = "pulsefiles.settings.operations.permanentDelete"
        static let clearIncompleteTransfers = "pulsefiles.settings.operations.clearIncompleteTransfers"
        static let liquidGlass = "pulsefiles.settings.appearance.liquidGlass"
        static let sidebarVisible = "pulsefiles.settings.appearance.sidebarVisible"
        static let singlePane = "pulsefiles.settings.appearance.singlePane"
        static let sidebarWidth = "pulsefiles.settings.appearance.sidebarWidth"
        static let resetPalette = "pulsefiles.settings.appearance.resetPalette"
        static let hiddenFiles = "pulsefiles.settings.navigation.hiddenFiles"
        static let quickSearchMatch = "pulsefiles.settings.navigation.quickSearchMatch"
        static let quickSearchPresentation = "pulsefiles.settings.navigation.quickSearchPresentation"
        static let grantFolderAccess = "pulsefiles.settings.access.grantFolder"
        static let terminalEnabled = "pulsefiles.settings.experimental.terminalEnabled"
        static let terminalVisible = "pulsefiles.settings.experimental.terminalVisible"
        static let experimentalSandbox = "pulsefiles.settings.experimental.sandbox"
        static func fileColor(_ category: FileVisualCategory) -> String { "pulsefiles.settings.appearance.color.\(category)" }
        static let scratchPath = "pulsefiles.settings.scratchFolder.path"
        static let chooseScratchFolder = "pulsefiles.settings.scratchFolder.choose"
        static let openScratchFolder = "pulsefiles.settings.scratchFolder.open"
        static let clearScratchFolder = "pulsefiles.settings.scratchFolder.clear"
    }

    enum CommandBar {
        static let panel = "pulsefiles.commandBar.panel"
        static let list = "pulsefiles.commandBar.list"
        static let field = "pulsefiles.commandBar.field"
    }

    enum QuickLocations {
        static let popover = "pulsefiles.quickLocations.popover"
        static let search = "pulsefiles.quickLocations.search"
        static let list = "pulsefiles.quickLocations.list"
        static func entry(_ id: String) -> String { "pulsefiles.quickLocations.entry.\(id)" }
    }

    enum Command {
        static func menuItem(_ command: MainCommand) -> String {
            "pulsefiles.command.\(String(describing: command))"
        }
    }

    enum Pattern {
        static let patternField = "pulsefiles.pattern.field"
        static let mode = "pulsefiles.pattern.mode"
        static let matchCount = "pulsefiles.pattern.matchCount"
        static let apply = "pulsefiles.pattern.apply"
        static let cancel = "pulsefiles.pattern.cancel"
    }

    enum FileOperationProgress {
        static let dialog = "pulsefiles.fileOperationProgress.dialog"
        static let indicator = "pulsefiles.fileOperationProgress.indicator"
        static let currentItemLabel = "pulsefiles.fileOperationProgress.currentItem"
        static let detailLabel = "pulsefiles.fileOperationProgress.detail"
        static let cancelButton = "pulsefiles.fileOperationProgress.cancel"
    }

    enum Terminal {
        static let panel = "pulsefiles.terminal.panel"
        static let textView = "pulsefiles.terminal.textView"
    }
}

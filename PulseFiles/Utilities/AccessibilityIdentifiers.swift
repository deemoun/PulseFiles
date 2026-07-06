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
    }

    enum Toolbar {
        static let searchField = "pulsefiles.toolbar.searchField"
        static let sidebarToggle = "pulsefiles.toolbar.sidebarToggle"
        static let terminalToggle = "pulsefiles.toolbar.terminalToggle"
    }

    enum Sidebar {
        static let panel = "pulsefiles.sidebar.panel"
        static let list = "pulsefiles.sidebar.list"
    }

    enum CommandBar {
        static let panel = "pulsefiles.commandBar.panel"
        static let list = "pulsefiles.commandBar.list"
        static let field = "pulsefiles.commandBar.field"
    }

    enum Terminal {
        static let panel = "pulsefiles.terminal.panel"
        static let textView = "pulsefiles.terminal.textView"
    }
}

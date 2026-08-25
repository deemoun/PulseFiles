import Foundation

#if DEBUG
/// Narrow, debug-only seam used by the deterministic AppKit UI harness.
/// It keeps the harness on the same controller routing used by menu and
/// keyboard actions without exposing mutable production UI state in releases.
extension MainWindowViewController {
    struct UIHarnessState: Equatable {
        let activePaneID: PaneID
        let leftDirectory: URL
        let rightDirectory: URL
        let leftSearchQuery: String
        let rightSearchQuery: String
        let leftFocusedURL: URL?
        let rightFocusedURL: URL?
        let leftMarkedURLs: [URL]
        let rightMarkedURLs: [URL]
    }

    var uiHarnessState: UIHarnessState {
        UIHarnessState(
            activePaneID: activePaneID,
            leftDirectory: leftPane.currentDirectory,
            rightDirectory: rightPane.currentDirectory,
            leftSearchQuery: leftPane.viewModel.searchQuery,
            rightSearchQuery: rightPane.viewModel.searchQuery,
            leftFocusedURL: leftPane.viewModel.focusedURL,
            rightFocusedURL: rightPane.viewModel.focusedURL,
            leftMarkedURLs: leftPane.selectedItems.map(\.url),
            rightMarkedURLs: rightPane.selectedItems.map(\.url)
        )
    }

    func uiHarnessNavigate(_ paneID: PaneID, to directory: URL) {
        activePaneID = paneID
        targetPane().navigate(to: directory)
    }

    func uiHarnessSetSearchQuery(_ query: String) {
        targetPane().setSearchQuery(query)
        toolbarSearchField?.stringValue = query
    }

    func uiHarnessPane(_ paneID: PaneID) -> FilePaneViewController {
        pane(for: paneID)
    }
}
#endif

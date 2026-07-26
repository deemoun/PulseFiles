import Foundation

enum SearchResultAction: Equatable { case open, reveal, navigate }
enum SearchResultActionRoute: Equatable { case perform(SearchResultAction, URL); case unavailable }

/// Pure preflight used by AppKit routing. Results are snapshots, so every
/// action rechecks scope, existence, and policy instead of trusting the row.
struct SearchResultActionRouter {
    func route(_ action: SearchResultAction, item: DescendantSearchItem, root: URL, canAccess: (URL) -> Bool, fileExists: (String) -> Bool) -> SearchResultActionRoute {
        guard canAccess(root), canAccess(item.url), FilePathComparison.isSameOrDescendant(item.url, ofDirectory: root), fileExists(item.url.path) else { return .unavailable }
        let destination = action == .navigate && (!item.isDirectory || item.isSymbolicLink) ? item.url.deletingLastPathComponent() : item.url
        guard canAccess(destination) else { return .unavailable }
        return .perform(action, destination)
    }
}

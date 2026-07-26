import Foundation

enum QuickLocationSection: String, CaseIterable {
    case ancestors, history, favorites, recent, volumes, workspace, oppositePane

    var title: String {
        switch self {
        case .ancestors: return "Parent Folders".localized
        case .history: return "History".localized
        case .favorites: return "Favorites".localized
        case .recent: return "Recent".localized
        case .volumes: return "Volumes".localized
        case .workspace: return "Temporary Workspace".localized
        case .oppositePane: return "Opposite Pane".localized
        }
    }
}

enum QuickLocationAvailability: Equatable {
    case available
    case accessDenied
    case unavailable

    var isNavigable: Bool { self == .available }
    var status: String? {
        switch self {
        case .available: return nil
        case .accessDenied: return "Access required".localized
        case .unavailable: return "Unavailable".localized
        }
    }
}

struct QuickLocationEntry: Identifiable, Equatable {
    let id: String
    let section: QuickLocationSection
    let title: String
    let url: URL
    let availability: QuickLocationAvailability

    var accessibilityIdentifier: String { AccessibilityIdentifiers.QuickLocations.entry(id) }
}

enum QuickLocationAssembler {
    static func assemble(
        activeDirectory: URL,
        history: NavigationHistory,
        bookmarks: [Bookmark],
        recent: [URL],
        volumes: [Volume],
        scratchDirectory: URL?,
        oppositeDirectory: URL?,
        canAccess: (URL) -> Bool,
        exists: (URL) -> Bool
    ) -> [QuickLocationEntry] {
        var candidates: [(QuickLocationSection, String, String, URL)] = []
        var parent = activeDirectory.deletingLastPathComponent()
        while parent.path != activeDirectory.path {
            candidates.append((.ancestors, "ancestor:\(parent.standardizedFileURL.path)", parent.lastPathComponent.isEmpty ? "/" : parent.lastPathComponent, parent))
            let next = parent.deletingLastPathComponent(); if next == parent { break }; parent = next
        }
        let historyURLs = Array(history.backStack.reversed()) + Array(history.forwardStack.reversed())
        candidates += historyURLs.map { (.history, "history:\($0.standardizedFileURL.path)", $0.lastPathComponent, $0) }
        candidates += bookmarks.map { (.favorites, "bookmark:\($0.id.uuidString)", $0.title, $0.url) }
        candidates += recent.map { (.recent, "recent:\($0.standardizedFileURL.path)", $0.lastPathComponent, $0) }
        candidates += volumes.map { (.volumes, "volume:\($0.url.standardizedFileURL.path)", $0.displayName, $0.url) }
        if let scratchDirectory { candidates.append((.workspace, "scratch", "Scratch Folder".localized, scratchDirectory)) }
        if let oppositeDirectory { candidates.append((.oppositePane, "opposite", oppositeDirectory.lastPathComponent, oppositeDirectory)) }
        var seen = Set<String>()
        return candidates.compactMap { section, id, title, url in
            guard seen.insert(id).inserted else { return nil }
            let availability: QuickLocationAvailability = !exists(url) ? .unavailable : (canAccess(url) ? .available : .accessDenied)
            return QuickLocationEntry(id: id, section: section, title: title.isEmpty ? url.path : title, url: url, availability: availability)
        }
    }
}

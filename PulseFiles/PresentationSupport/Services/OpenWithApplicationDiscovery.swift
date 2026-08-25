import AppKit

/// Looks up the applications that macOS reports can open a file. Keeping this
/// work behind an async dependency prevents NSWorkspace lookups from delaying a
/// context-menu request.
package protocol OpenWithApplicationDiscovering: Sendable {
    func applicationURLs(for fileURL: URL) async throws -> [URL]
}

package final class NSWorkspaceOpenWithApplicationDiscovery: OpenWithApplicationDiscovering, @unchecked Sendable {
    package func applicationURLs(for fileURL: URL) async throws -> [URL] {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        }.value
    }
}

/// Applies asynchronous application-discovery results to an Open With submenu.
/// A result is ignored if its original menu item no longer owns that submenu.
@MainActor
package final class OpenWithMenuApplicationResolver {
    private let discovery: any OpenWithApplicationDiscovering

    package init(discovery: any OpenWithApplicationDiscovering = NSWorkspaceOpenWithApplicationDiscovery()) {
        self.discovery = discovery
    }

    package func resolveApplications(
        for fileURL: URL,
        menuItem: NSMenuItem,
        submenu: NSMenu,
        loadingItem: NSMenuItem,
        makeApplicationItem: @escaping (URL) -> NSMenuItem
    ) {
        Task { [weak menuItem, weak submenu, weak loadingItem] in
            do {
                let applicationURLs = try await discovery.applicationURLs(for: fileURL)
                guard let menuItem,
                      let submenu,
                      let loadingItem,
                      menuItem.submenu === submenu,
                      submenu.items.contains(where: { $0 === loadingItem }) else {
                    return
                }

                guard !Task.isCancelled else {
                    submenu.removeItem(loadingItem)
                    return
                }

                submenu.removeItem(loadingItem)
                let sortedURLs = applicationURLs.sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }
                guard !sortedURLs.isEmpty else { return }

                submenu.addItem(.separator())
                sortedURLs.forEach { submenu.addItem(makeApplicationItem($0)) }
            } catch {
                // The default action remains usable when lookup is cancelled or
                // NSWorkspace cannot provide an application list.
                guard let menuItem,
                      let submenu,
                      let loadingItem,
                      menuItem.submenu === submenu,
                      submenu.items.contains(where: { $0 === loadingItem }) else {
                    return
                }
                submenu.removeItem(loadingItem)
            }
        }
    }
}

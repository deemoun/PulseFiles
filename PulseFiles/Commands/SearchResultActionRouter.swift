// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import PulseFilesServices
import Foundation

package enum SearchResultAction: Equatable { case open, reveal, navigate }
package enum SearchResultActionRoute: Equatable { case perform(SearchResultAction, URL); case unavailable }

/// Pure preflight used by AppKit routing. Results are snapshots, so every
/// action rechecks scope, existence, and policy instead of trusting the row.
package struct SearchResultActionRouter {
    package init() {}

    package func route(_ action: SearchResultAction, item: DescendantSearchItem, root: URL, canAccess: (URL) -> Bool, fileExists: (String) -> Bool) -> SearchResultActionRoute {
        guard canAccess(root), canAccess(item.url), FilePathComparison.isSameOrDescendant(item.url, ofDirectory: root), fileExists(item.url.path) else { return .unavailable }
        let destination = action == .navigate && (!item.isDirectory || item.isSymbolicLink) ? item.url.deletingLastPathComponent() : item.url
        guard canAccess(destination) else { return .unavailable }
        return .perform(action, destination)
    }
}

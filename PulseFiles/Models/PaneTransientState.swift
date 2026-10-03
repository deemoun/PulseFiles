// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// AppKit-free URL selection memory used while a pane listing is replaced.
package struct PaneSelectionRestorationState: Equatable {
    package private(set) var pendingURL: URL?
    package private(set) var previousURLs: [URL] = []

    package init() {}

    package mutating func prepare(_ url: URL?) { pendingURL = url }
    package mutating func reset() { pendingURL = nil; previousURLs = [] }
    package mutating func record(_ urls: [URL]) { previousURLs = urls }

    package mutating func consumePending(ifAvailable urls: [URL], normalize: (URL) -> String) -> URL? {
        guard let pendingURL else { return nil }
        let pendingPath = normalize(pendingURL)
        guard urls.contains(where: { normalize($0) == pendingPath }) else { return nil }
        self.pendingURL = nil
        return pendingURL
    }

    package func indexes(in urls: [URL], normalize: (URL) -> String) -> IndexSet {
        let paths = Set(previousURLs.map(normalize))
        return IndexSet(urls.enumerated().compactMap { paths.contains(normalize($0.element)) ? $0.offset : nil })
    }
}

/// The transient focus captured when quick search starts.
package struct PaneQuickSearchState: Equatable {
    package private(set) var focusedURLBeforeSearch: URL?

    package init() {}

    package mutating func transition(from oldQuery: String, to newQuery: String, focusedURL: URL?) {
        if oldQuery.isEmpty, !newQuery.isEmpty { focusedURLBeforeSearch = focusedURL }
        if newQuery.isEmpty { focusedURLBeforeSearch = nil }
    }
}

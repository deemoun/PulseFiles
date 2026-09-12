// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An immutable search match shared by services, workflows, and presentation.
package struct DescendantSearchItem: Equatable {
    package let url: URL
    package let name: String
    package let pathContext: String
    package let typeDescription: String
    package let isDirectory: Bool
    package let isSymbolicLink: Bool
    package let size: Int64?
    package let modificationDate: Date?

    package init(url: URL, name: String, pathContext: String, typeDescription: String, isDirectory: Bool, isSymbolicLink: Bool, size: Int64? = nil, modificationDate: Date? = nil) {
        self.url = url
        self.name = name
        self.pathContext = pathContext
        self.typeDescription = typeDescription
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// An immutable description of what a descendant search should match.
package struct DescendantSearchQuery: Equatable {
    package enum NameMatcher: Equatable { case glob(String), regularExpression(String) }
    package enum FileKind: Equatable { case file, directory, symbolicLink }
    package struct SizePredicate: Equatable {
        package let minimumBytes: Int64?
        package let maximumBytes: Int64?
        package init(minimumBytes: Int64? = nil, maximumBytes: Int64? = nil) {
            self.minimumBytes = minimumBytes; self.maximumBytes = maximumBytes
        }
    }
    package struct DatePredicate: Equatable {
        package let earliest: Date?
        package let latest: Date?
        package init(earliest: Date? = nil, latest: Date? = nil) {
            self.earliest = earliest; self.latest = latest
        }
    }
    package enum Scope: Equatable { case folder(URL, includeDescendants: Bool) }

    package let nameMatcher: NameMatcher
    package let fileKinds: Set<FileKind>
    package let size: SizePredicate?
    package let modificationDate: DatePredicate?
    package let scopes: [Scope]

    package init(nameMatcher: NameMatcher, fileKinds: Set<FileKind> = [], size: SizePredicate? = nil, modificationDate: DatePredicate? = nil, scopes: [Scope]) {
        self.nameMatcher = nameMatcher; self.fileKinds = fileKinds; self.size = size
        self.modificationDate = modificationDate; self.scopes = scopes
    }
}

/// The immutable outcome returned by descendant-search execution.
package struct DescendantSearchResult {
    package let items: [DescendantSearchItem]
    package let wasCancelled: Bool
    package let hitItemLimit: Bool
    package let hitDepthLimit: Bool
    package let timedOut: Bool
    package let inaccessibleURLs: [URL]
    package var isPartial: Bool { wasCancelled || hitItemLimit || hitDepthLimit || timedOut || !inaccessibleURLs.isEmpty }

    package init(items: [DescendantSearchItem], wasCancelled: Bool, hitItemLimit: Bool, hitDepthLimit: Bool, timedOut: Bool, inaccessibleURLs: [URL]) {
        self.items = items; self.wasCancelled = wasCancelled; self.hitItemLimit = hitItemLimit
        self.hitDepthLimit = hitDepthLimit; self.timedOut = timedOut; self.inaccessibleURLs = inaccessibleURLs
    }
}

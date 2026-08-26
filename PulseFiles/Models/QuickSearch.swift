// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesUtilities

package enum QuickSearchMatchMode: String, Codable, CaseIterable {
    case fuzzy
    case contains
    case prefix
    case suffix
    case prefixOrSuffix
}

package enum QuickSearchPresentation: String, Codable, CaseIterable {
    case filterMatches
    case showAllAndHighlightMatches
}

/// A match expressed in the original string, so callers can decorate text
/// without replacing its spelling or performing another lookup.
package struct QuickSearchMatch: Equatable {
    package let ranges: [Range<String.Index>]
}

package enum QuickSearchMatcher {
    package static func match(_ query: String, in candidate: String, mode: QuickSearchMatchMode) -> QuickSearchMatch? {
        let needle = characters(query)
        let haystack = characters(candidate)
        guard !needle.isEmpty else { return QuickSearchMatch(ranges: []) }
        guard !haystack.isEmpty else { return nil }

        let indexes: [Int]?
        switch mode {
        case .fuzzy:
            indexes = fuzzyIndexes(needle, in: haystack)
        case .contains:
            indexes = contiguousIndexes(needle, in: haystack, positions: 0...max(0, haystack.count - needle.count)).first
        case .prefix:
            indexes = contiguousIndexes(needle, in: haystack, positions: 0...0).first
        case .suffix:
            let start = haystack.count - needle.count
            indexes = start >= 0 ? contiguousIndexes(needle, in: haystack, positions: start...start).first : nil
        case .prefixOrSuffix:
            let suffixStart = haystack.count - needle.count
            indexes = contiguousIndexes(needle, in: haystack, positions: 0...0).first
                ?? (suffixStart >= 0 ? contiguousIndexes(needle, in: haystack, positions: suffixStart...suffixStart).first : nil)
        }
        guard let indexes else { return nil }
        return QuickSearchMatch(ranges: coalescedRanges(for: indexes, in: candidate))
    }

    private static func characters(_ value: String) -> [String] {
        value.map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    }

    private static func fuzzyIndexes(_ needle: [String], in haystack: [String]) -> [Int]? {
        var result: [Int] = []
        var cursor = 0
        for character in needle {
            guard let found = haystack[cursor...].firstIndex(of: character) else { return nil }
            result.append(found)
            cursor = found + 1
        }
        return result
    }

    private static func contiguousIndexes(_ needle: [String], in haystack: [String], positions: ClosedRange<Int>) -> [[Int]] {
        guard needle.count <= haystack.count else { return [] }
        return positions.compactMap { start in
            guard start >= 0, start + needle.count <= haystack.count,
                  Array(haystack[start..<(start + needle.count)]) == needle else { return nil }
            return Array(start..<(start + needle.count))
        }
    }

    private static func coalescedRanges(for offsets: [Int], in value: String) -> [Range<String.Index>] {
        guard let first = offsets.first else { return [] }
        var groups: [[Int]] = [[first]]
        for offset in offsets.dropFirst() {
            if offset == groups[groups.count - 1].last! + 1 { groups[groups.count - 1].append(offset) }
            else { groups.append([offset]) }
        }
        return groups.map { group in
            let lower = value.index(value.startIndex, offsetBy: group[0])
            let upper = value.index(value.startIndex, offsetBy: group.last! + 1)
            return lower..<upper
        }
    }
}

import Foundation
import PulseFilesUtilities

package enum FilePatternMode: Equatable {
    case glob
    case regularExpression
}

package struct FilePatternMatchResult: Equatable {
    package let matchingURLs: Set<URL>
    package let sampleNames: [String]
    package let totalCount: Int
}

/// Matches one directory snapshot supplied by the caller. It never traverses the
/// filesystem, which keeps pattern selection scoped to the pane's visible items.
package struct FilePatternMatcher {
    package static let defaultPreviewLimit = 8

    package static func validationError(pattern: String, mode: FilePatternMode) -> String? {
        guard mode == .regularExpression else { return nil }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    package static func matches(
        pattern: String,
        mode: FilePatternMode,
        items: [FileItem],
        previewLimit: Int = defaultPreviewLimit
    ) throws -> FilePatternMatchResult {
        let expression = try NSRegularExpression(
            pattern: mode == .glob ? globRegularExpression(pattern) : pattern,
            options: [.caseInsensitive]
        )
        let matches = items.filter { item in
            let range = NSRange(item.filename.startIndex..<item.filename.endIndex, in: item.filename)
            return expression.firstMatch(in: item.filename, options: [], range: range) != nil
        }
        return FilePatternMatchResult(
            matchingURLs: Set(matches.map(\.url)),
            sampleNames: Array(matches.prefix(max(0, previewLimit)).map(\.filename)),
            totalCount: matches.count
        )
    }

    package static func globRegularExpression(_ glob: String) -> String {
        var result = "^"
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            switch character {
            case "*": result += ".*"
            case "?": result += "."
            case "[":
                if let close = glob[glob.index(after: index)...].firstIndex(of: "]") {
                    var contents = String(glob[glob.index(after: index)..<close])
                    if contents.first == "!" { contents.replaceSubrange(contents.startIndex...contents.startIndex, with: "^") }
                    result += "[" + contents.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                    index = close
                } else {
                    result += "\\["
                }
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = glob.index(after: index)
        }
        return result + "$"
    }
}

package enum MarkMutation: Equatable {
    case select
    case deselect

    package func applying(matches: Set<URL>, to marks: Set<URL>) -> Set<URL> {
        switch self {
        case .select: return marks.union(matches)
        case .deselect: return marks.subtracting(matches)
        }
    }
}

package enum SameExtensionMatcher {
    /// Extension comparisons are case-insensitive. An extensionless focused item
    /// matches every other extensionless visible item (including directories).
    package static func matchingURLs(focusedItem: FileItem?, visibleItems: [FileItem]) -> Set<URL>? {
        guard let focusedItem else { return nil }
        let extensionKey = focusedItem.fileExtension.lowercased()
        return Set(visibleItems.lazy.filter { $0.fileExtension.lowercased() == extensionKey }.map(\.url))
    }
}

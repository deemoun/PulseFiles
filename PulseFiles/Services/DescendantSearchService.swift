import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// Bounded, policy-aware recursive search. Symbolic links may be returned but
/// are never followed.
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
        self.url = url; self.name = name; self.pathContext = pathContext; self.typeDescription = typeDescription
        self.isDirectory = isDirectory; self.isSymbolicLink = isSymbolicLink; self.size = size; self.modificationDate = modificationDate
    }
}

package struct DescendantSearchQuery: Equatable {
    package enum NameMatcher: Equatable { case glob(String), regularExpression(String) }
    package enum FileKind: Equatable { case file, directory, symbolicLink }
    package struct SizePredicate: Equatable { var minimumBytes: Int64?; var maximumBytes: Int64? }
    package struct DatePredicate: Equatable { var earliest: Date?; var latest: Date? }
    package enum Scope: Equatable { case folder(URL, includeDescendants: Bool) }

    package var nameMatcher: NameMatcher
    package var fileKinds: Set<FileKind> = []
    package var size: SizePredicate?
    package var modificationDate: DatePredicate?
    package var scopes: [Scope]

    package init(nameMatcher: NameMatcher, fileKinds: Set<FileKind> = [], size: SizePredicate? = nil, modificationDate: DatePredicate? = nil, scopes: [Scope]) {
        self.nameMatcher = nameMatcher; self.fileKinds = fileKinds; self.size = size; self.modificationDate = modificationDate; self.scopes = scopes
    }
}

package enum DescendantSearchError: LocalizedError, Equatable {
    case emptyPattern
    case malformedRegularExpression(String)
    case invalidSizeRange
    case invalidDateRange
    case noScopes

    package var errorDescription: String? {
        switch self {
        case .emptyPattern: return "Enter a name pattern."
        case .malformedRegularExpression(let detail): return "Invalid regular expression: \(detail)"
        case .invalidSizeRange: return "The minimum size must not exceed the maximum size."
        case .invalidDateRange: return "The earliest date must not be later than the latest date."
        case .noScopes: return "Choose at least one search folder."
        }
    }
}

package struct DescendantSearchLimits: Equatable {
    package var maximumItems = 10_000
    package var maximumDepth = 32
    package var timeout: TimeInterval = 10
    package var batchSize = 100

    package init(maximumItems: Int = 10_000, maximumDepth: Int = 32, timeout: TimeInterval = 10, batchSize: Int = 100) {
        self.maximumItems = maximumItems
        self.maximumDepth = maximumDepth
        self.timeout = timeout
        self.batchSize = batchSize
    }
}

package struct DescendantSearchResult {
    package let items: [DescendantSearchItem]
    package let wasCancelled: Bool
    package let hitItemLimit: Bool
    package let hitDepthLimit: Bool
    package let timedOut: Bool
    package let inaccessibleURLs: [URL]
    package var isPartial: Bool { wasCancelled || hitItemLimit || hitDepthLimit || timedOut || !inaccessibleURLs.isEmpty }
}

package typealias DescendantSearchBatchHandler = @Sendable ([DescendantSearchItem]) async -> Void

package final class DescendantSearchService {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    package init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager; self.accessPolicy = accessPolicy
    }

    /// Compatibility entry point: a plain string is a case-insensitive glob fragment.
    package func search(query: String, rootURL: URL, limits: DescendantSearchLimits = .init()) async throws -> DescendantSearchResult {
        try await search(query: .init(nameMatcher: .glob("*\(query.trimmingCharacters(in: .whitespacesAndNewlines))*"), scopes: [.folder(rootURL, includeDescendants: true)]), limits: limits)
    }

    package func search(query: DescendantSearchQuery, limits: DescendantSearchLimits = .init(), onBatch: DescendantSearchBatchHandler? = nil) async throws -> DescendantSearchResult {
        let matcher = try Self.compile(query)
        guard !query.scopes.isEmpty else { throw DescendantSearchError.noScopes }
        let roots = query.scopes.map { scope -> URL in if case .folder(let url, _) = scope { return url }; fatalError() }
        return try await accessPolicy.withValidatedAccess(to: roots) {
            let worker = Task.detached(priority: .userInitiated) { [fileManager, accessPolicy] in
                let started = Date(); var items: [DescendantSearchItem] = []; var batch: [DescendantSearchItem] = []
                var inaccessible = Set<URL>(); var cancelled = false; var itemLimit = false; var depthLimit = false; var timedOut = false
                let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .localizedTypeDescriptionKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
                searchLoop: for scope in query.scopes {
                    let (root, recursive): (URL, Bool)
                    switch scope {
                    case .folder(let url, let includeDescendants):
                        (root, recursive) = (url, includeDescendants)
                    }
                    let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in inaccessible.insert(url); return true })
                    while let url = enumerator?.nextObject() as? URL {
                        if Task.isCancelled { cancelled = true; break searchLoop }
                        if Date().timeIntervalSince(started) >= limits.timeout { timedOut = true; break searchLoop }
                        let depth = url.pathComponents.count - root.pathComponents.count
                        if !recursive && depth > 1 { enumerator?.skipDescendants(); continue }
                        if depth > limits.maximumDepth { depthLimit = true; enumerator?.skipDescendants(); continue }
                        do { try accessPolicy.validateAccess(to: url) } catch { inaccessible.insert(url); enumerator?.skipDescendants(); continue }
                        do {
                            let values = try url.resourceValues(forKeys: keys); let isLink = values.isSymbolicLink == true
                            if isLink { enumerator?.skipDescendants() }
                            let name = values.name ?? url.lastPathComponent
                            let kind: DescendantSearchQuery.FileKind = isLink ? .symbolicLink : (values.isDirectory == true ? .directory : .file)
                            let byteSize = values.fileSize.map(Int64.init); let date = values.contentModificationDate
                            guard matcher(name), (query.fileKinds.isEmpty || query.fileKinds.contains(kind)), Self.matches(byteSize, query.size), Self.matches(date, query.modificationDate) else { continue }
                            let item = DescendantSearchItem(url: url, name: name, pathContext: url.deletingLastPathComponent().path, typeDescription: values.localizedTypeDescription ?? (isLink ? "Symbolic Link" : (values.isDirectory == true ? "Folder" : "File")), isDirectory: values.isDirectory == true, isSymbolicLink: isLink, size: byteSize, modificationDate: date)
                            items.append(item); batch.append(item)
                            if batch.count >= max(1, limits.batchSize) { await onBatch?(batch); batch.removeAll(keepingCapacity: true) }
                            if items.count >= max(0, limits.maximumItems) { itemLimit = true; break searchLoop }
                        } catch { inaccessible.insert(url); enumerator?.skipDescendants() }
                    }
                }
                if !batch.isEmpty { await onBatch?(batch) }
                return DescendantSearchResult(items: items, wasCancelled: cancelled, hitItemLimit: itemLimit, hitDepthLimit: depthLimit, timedOut: timedOut, inaccessibleURLs: inaccessible.sorted { $0.path < $1.path })
            }
            return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        }
    }

    private static func compile(_ query: DescendantSearchQuery) throws -> (String) -> Bool {
        let pattern: String
        switch query.nameMatcher {
        case .glob(let glob):
            guard !glob.isEmpty else { throw DescendantSearchError.emptyPattern }
            pattern = "^" + NSRegularExpression.escapedPattern(for: glob).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        case .regularExpression(let regex): guard !regex.isEmpty else { throw DescendantSearchError.emptyPattern }; pattern = regex
        }
        if let size = query.size, let min = size.minimumBytes, let max = size.maximumBytes, min > max { throw DescendantSearchError.invalidSizeRange }
        if let date = query.modificationDate, let min = date.earliest, let max = date.latest, min > max { throw DescendantSearchError.invalidDateRange }
        do { let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]); return { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil } }
        catch { throw DescendantSearchError.malformedRegularExpression(error.localizedDescription) }
    }

    private static func matches(_ value: Int64?, _ predicate: DescendantSearchQuery.SizePredicate?) -> Bool {
        guard let predicate else { return true }; guard let value else { return false }
        return (predicate.minimumBytes.map { value >= $0 } ?? true) && (predicate.maximumBytes.map { value <= $0 } ?? true)
    }
    private static func matches(_ value: Date?, _ predicate: DescendantSearchQuery.DatePredicate?) -> Bool {
        guard let predicate else { return true }; guard let value else { return false }
        return (predicate.earliest.map { value >= $0 } ?? true) && (predicate.latest.map { value <= $0 } ?? true)
    }
}

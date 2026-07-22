import Foundation
import UniformTypeIdentifiers

/// Bounded, policy-aware recursive filename search. This deliberately does not
/// resolve symbolic links: a link may be reported, but its target is never read
/// or enumerated.
struct DescendantSearchItem: Equatable {
    let url: URL
    let name: String
    let pathContext: String
    let typeDescription: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
}

struct DescendantSearchLimits: Equatable {
    var maximumItems = 10_000
    var maximumDepth = 32
    var timeout: TimeInterval = 10
}

struct DescendantSearchResult {
    let items: [DescendantSearchItem]
    let wasCancelled: Bool
    let hitItemLimit: Bool
    let hitDepthLimit: Bool
    let timedOut: Bool
    let inaccessibleURLs: [URL]

    var isPartial: Bool { wasCancelled || hitItemLimit || hitDepthLimit || timedOut || !inaccessibleURLs.isEmpty }
}

final class DescendantSearchService {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    func search(query: String, rootURL: URL, limits: DescendantSearchLimits = .init()) async throws -> DescendantSearchResult {
        try accessPolicy.validateAccess(to: rootURL)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return DescendantSearchResult(items: [], wasCancelled: false, hitItemLimit: false, hitDepthLimit: false, timedOut: false, inaccessibleURLs: []) }
        return try await accessPolicy.withAccess(to: [rootURL]) {
            let worker = Task.detached(priority: .userInitiated) { [fileManager, accessPolicy] in
                let started = Date()
                var items: [DescendantSearchItem] = []
                var inaccessible = Set<URL>()
                var cancelled = false, itemLimit = false, depthLimit = false, timedOut = false
                let keys: Set<URLResourceKey> = [.nameKey, .isDirectoryKey, .isSymbolicLinkKey, .localizedTypeDescriptionKey, .isPackageKey]
                let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { url, _ in inaccessible.insert(url); return true }
                )
                while let url = enumerator?.nextObject() as? URL {
                    if Task.isCancelled { cancelled = true; break }
                    if Date().timeIntervalSince(started) >= limits.timeout { timedOut = true; break }
                    let depth = url.pathComponents.count - rootURL.pathComponents.count
                    if depth > limits.maximumDepth { depthLimit = true; enumerator?.skipDescendants(); continue }
                    do { try accessPolicy.validateAccess(to: url) }
                    catch { inaccessible.insert(url); enumerator?.skipDescendants(); continue }
                    do {
                        let values = try url.resourceValues(forKeys: keys)
                        let isLink = values.isSymbolicLink == true
                        if isLink { enumerator?.skipDescendants() }
                        let name = values.name ?? url.lastPathComponent
                        if name.localizedCaseInsensitiveContains(query) {
                            let isDirectory = values.isDirectory == true
                            let type = values.localizedTypeDescription ?? (isLink ? "Symbolic Link" : (isDirectory ? "Folder" : "File"))
                            items.append(DescendantSearchItem(url: url, name: name, pathContext: url.deletingLastPathComponent().path, typeDescription: type, isDirectory: isDirectory, isSymbolicLink: isLink))
                            if items.count >= limits.maximumItems { itemLimit = true; break }
                        }
                    } catch { inaccessible.insert(url); enumerator?.skipDescendants() }
                }
                return DescendantSearchResult(items: items, wasCancelled: cancelled, hitItemLimit: itemLimit, hitDepthLimit: depthLimit, timedOut: timedOut, inaccessibleURLs: inaccessible.sorted { $0.path < $1.path })
            }
            return try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: {
                worker.cancel()
            })
        }
    }
}

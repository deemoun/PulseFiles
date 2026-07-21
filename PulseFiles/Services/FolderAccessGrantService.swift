import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct FolderAccessGrant: Codable, Equatable {
    let url: URL
    let bookmarkData: Data
}

struct FolderAccessScope {
    fileprivate let urls: [URL]

    var isActive: Bool {
        !urls.isEmpty
    }
}

protocol FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data
    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool)
}

struct SystemFolderAccessBookmarkResolver: FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}

final class FolderAccessGrantService {
    static let shared = FolderAccessGrantService()

    static let defaultsKey = "folderAccessGrants"

    private let defaults: UserDefaults
    private let resolver: FolderAccessBookmarkResolving
    private let fileManager: FileManager
    private var resolvedGrants: [String: URL] = [:]
    private(set) var staleGrantURLs: [URL] = []

    init(
        defaults: UserDefaults = .standard,
        resolver: FolderAccessBookmarkResolving = SystemFolderAccessBookmarkResolver(),
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.resolver = resolver
        self.fileManager = fileManager
        resolveStoredBookmarks()
    }

    var grants: [FolderAccessGrant] {
        get {
            guard let data = defaults.data(forKey: Self.defaultsKey),
                  let grants = try? JSONDecoder().decode([FolderAccessGrant].self, from: data) else { return [] }
            return grants
        }
        set {
            _ = store(newValue)
        }
    }

    @discardableResult
    func grantAccess(to directory: URL) throws -> FolderAccessGrant {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let standardizedDirectory = directory.standardizedFileURL
        if let existingGrant = grant(containing: standardizedDirectory) {
            return existingGrant
        }

        let bookmarkData = try resolver.makeBookmarkData(for: standardizedDirectory)
        let grant = FolderAccessGrant(url: standardizedDirectory, bookmarkData: bookmarkData)
        upsert(grant)
        resolveStoredBookmarks()
        return grant
    }

    #if canImport(AppKit)
    @MainActor
    func requestGrant(startingAt directory: URL?, window: NSWindow?, completion: @escaping (Result<URL, Error>) -> Void) {
        if let directory, let existingGrant = grant(containing: directory) {
            completion(.success(existingGrant.url))
            return
        }

        let panel = NSOpenPanel()
        panel.directoryURL = directory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access".localized
        panel.message = "Choose a folder to grant PulseFiles access.".localized

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let selectedURL = panel.url else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            do {
                let grant = try self.grantAccess(to: selectedURL)
                completion(.success(grant.url))
            } catch {
                completion(.failure(error))
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
    #endif

    func resolveStoredBookmarks() {
        resolvedGrants.removeAll()
        staleGrantURLs.removeAll()
        var resolvedStoredGrants: [FolderAccessGrant] = []
        var shouldRewriteStoredGrants = false

        for grant in grants {
            do {
                let resolved = try resolver.resolveBookmarkData(grant.bookmarkData)
                let standardized = resolved.url.standardizedFileURL
                resolvedGrants[normalizedPath(standardized)] = standardized
                var resolvedGrant = FolderAccessGrant(url: standardized, bookmarkData: grant.bookmarkData)
                if resolved.isStale {
                    do {
                        resolvedGrant = FolderAccessGrant(
                            url: standardized,
                            bookmarkData: try resolver.makeBookmarkData(for: standardized)
                        )
                        shouldRewriteStoredGrants = true
                    } catch {
                        staleGrantURLs.append(standardized)
                    }
                }
                if resolvedGrant.url != grant.url.standardizedFileURL {
                    shouldRewriteStoredGrants = true
                }
                resolvedStoredGrants.append(resolvedGrant)
            } catch {
                staleGrantURLs.append(grant.url)
                resolvedStoredGrants.append(grant)
            }
        }

        let compactedGrants = compacted(resolvedStoredGrants)
        if compactedGrants != resolvedStoredGrants {
            shouldRewriteStoredGrants = true
        }
        if shouldRewriteStoredGrants {
            _ = store(compactedGrants)
        }
    }

    /// Refreshes bookmark resolution after folders have moved, become available, or been reauthorized.
    func refreshResolvedGrants() {
        resolveStoredBookmarks()
    }

    /// Removes the persisted capability for a folder and immediately refreshes the resolved state.
    @discardableResult
    func removeGrant(for directory: URL) -> Bool {
        let path = normalizedPath(directory)
        let stored = grants
        let remaining = stored.filter { normalizedPath($0.url) != path }
        guard remaining.count != stored.count, store(remaining) else { return false }
        resolveStoredBookmarks()
        return true
    }

    func hasGrant(containing url: URL) -> Bool {
        resolvedGrant(containing: url) != nil
    }

    func withSecurityScopedAccess<T>(to urls: [URL], _ body: () throws -> T) rethrows -> T {
        let scope = beginSecurityScopedAccess(to: urls)
        defer { endSecurityScopedAccess(scope) }
        return try body()
    }

    func withSecurityScopedAccess<T>(to urls: [URL], _ body: () async throws -> T) async rethrows -> T {
        let scope = beginSecurityScopedAccess(to: urls)
        defer { endSecurityScopedAccess(scope) }
        return try await body()
    }

    func beginSecurityScopedAccess(to urls: [URL]) -> FolderAccessScope {
        FolderAccessScope(urls: startAccessing(urls))
    }

    func endSecurityScopedAccess(_ scope: FolderAccessScope) {
        stopAccessing(scope.urls)
    }

    private func upsert(_ grant: FolderAccessGrant) {
        let path = normalizedPath(grant.url)
        var stored = grants.filter {
            let storedPath = normalizedPath($0.url)
            return storedPath != path && !storedPath.hasPrefix(path + "/")
        }
        stored.append(grant)
        grants = compacted(stored)
    }

    private func grant(containing url: URL) -> FolderAccessGrant? {
        let candidate = normalizedPath(url)
        return grants.first { grant in
            let grantPath = normalizedPath(grant.url)
            return candidate == grantPath || candidate.hasPrefix(grantPath + "/")
        }
    }

    private func compacted(_ grants: [FolderAccessGrant]) -> [FolderAccessGrant] {
        let sorted = grants.sorted {
            normalizedPath($0.url).count < normalizedPath($1.url).count
        }
        return sorted.reduce(into: [FolderAccessGrant]()) { kept, grant in
            let path = normalizedPath(grant.url)
            guard kept.contains(where: { existing in
                let existingPath = normalizedPath(existing.url)
                return path == existingPath || path.hasPrefix(existingPath + "/")
            }) == false else { return }
            kept.append(grant)
        }
    }

    @discardableResult
    private func store(_ grants: [FolderAccessGrant]) -> Bool {
        if grants.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
            return true
        }
        guard let data = try? JSONEncoder().encode(grants) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }

    private func startAccessing(_ urls: [URL]) -> [URL] {
        var started: [URL] = []
        var seen = Set<String>()
        for url in urls.compactMap({ resolvedGrant(containing: $0) }) {
            guard seen.insert(normalizedPath(url)).inserted else { continue }
            if url.startAccessingSecurityScopedResource() {
                started.append(url)
            }
        }
        return started
    }

    private func stopAccessing(_ urls: [URL]) {
        urls.reversed().forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func resolvedGrant(containing url: URL) -> URL? {
        let candidate = normalizedPath(url)
        return resolvedGrants.values.first { grantURL in
            let grantPath = normalizedPath(grantURL)
            return candidate == grantPath || candidate.hasPrefix(grantPath + "/")
        }
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

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
            if newValue.isEmpty {
                defaults.removeObject(forKey: Self.defaultsKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    @discardableResult
    func grantAccess(to directory: URL) throws -> FolderAccessGrant {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let bookmarkData = try resolver.makeBookmarkData(for: directory)
        let grant = FolderAccessGrant(url: directory.standardizedFileURL, bookmarkData: bookmarkData)
        upsert(grant)
        resolveStoredBookmarks()
        return grant
    }

    #if canImport(AppKit)
    @MainActor
    func requestGrant(startingAt directory: URL?, window: NSWindow?, completion: @escaping (Result<URL, Error>) -> Void) {
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
        for grant in grants {
            do {
                let resolved = try resolver.resolveBookmarkData(grant.bookmarkData)
                let standardized = resolved.url.standardizedFileURL
                resolvedGrants[normalizedPath(standardized)] = standardized
                if resolved.isStale {
                    staleGrantURLs.append(standardized)
                }
            } catch {
                staleGrantURLs.append(grant.url)
            }
        }
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
        var stored = grants.filter { normalizedPath($0.url) != path }
        stored.append(grant)
        grants = stored
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

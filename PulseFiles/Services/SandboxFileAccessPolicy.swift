#if canImport(AppKit)
import AppKit
#endif
import Foundation

enum SandboxAccessError: LocalizedError, Equatable {
    case outsideExperimentalSandbox(URL)
    case unauthorized(URL)

    var errorDescription: String? {
        switch self {
        case .outsideExperimentalSandbox:
            return "Experimental sandbox mode is enabled.".localized
        case .unauthorized:
            return "Folder access is not authorized.".localized
        }
    }

    var failureReason: String? {
        switch self {
        case .outsideExperimentalSandbox(let url):
            return "%@ is outside the PulseFiles experimental sandbox.".localized(with: url.path)
        case .unauthorized(let url):
            return "%@ is not currently readable by PulseFiles. Choose a folder you can access or grant access first.".localized(with: url.path)
        }
    }
}

struct SandboxFileAccessPolicy {
    struct AccessProbe {
        let fileExists: (String) -> Bool
        let isReadableFile: (String) -> Bool
        let isWritableFile: (String) -> Bool

        static let fileManagerDefault = AccessProbe(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isReadableFile: { FileManager.default.isReadableFile(atPath: $0) },
            isWritableFile: { FileManager.default.isWritableFile(atPath: $0) }
        )
    }

    private let isEnabledOverride: Bool?
    private let grantService: FolderAccessGrantService
    private let accessProbe: AccessProbe
    let rootURL: URL

    static let current = SandboxFileAccessPolicy(
        rootURL: ExperimentalFlags.appSandboxRoot
    )

    init(
        isEnabled: Bool? = nil,
        rootURL: URL,
        grantService: FolderAccessGrantService = .shared,
        accessProbe: AccessProbe = .fileManagerDefault
    ) {
        self.isEnabledOverride = isEnabled
        self.rootURL = rootURL
        self.grantService = grantService
        self.accessProbe = accessProbe
    }

    var isEnabled: Bool {
        isEnabledOverride ?? ExperimentalFlags.restrictFileAccessToAppSandboxRoot
    }

    func canAccess(_ url: URL, logDecision shouldLogDecision: Bool = true) -> Bool {
        let allowed: Bool
        let reason: String
        if isEnabled {
            if isInsideExperimentalSandbox(url) {
                allowed = true
                reason = "inside sandbox root"
            } else if grantService.hasGrant(containing: url) {
                allowed = true
                reason = "explicit folder access grant"
            } else {
                allowed = false
                reason = "outside sandbox root and not explicitly granted"
            }
        } else {
            allowed = hasProcessAccess(to: url) || grantService.hasGrant(containing: url)
            reason = allowed ? "directly readable, security-scoped, or granted" : "not readable or not authorized"
        }
        if shouldLogDecision {
            logDecision(allowed ? .debug : .warning, allowed: allowed, url: url, reason: reason)
        }
        return allowed
    }

    func validateAccess(to url: URL) throws {
        guard canAccess(url) else {
            let reason = isEnabled ? "outside sandbox root" : "not readable or not authorized"
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied access validation: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
            throw isEnabled ? SandboxAccessError.outsideExperimentalSandbox(url) : SandboxAccessError.unauthorized(url)
        }
    }

    func validateDestinationAccess(to destination: URL) throws {
        let parentDirectory = destination.deletingLastPathComponent()
        let allowed: Bool
        let reason: String

        if isEnabled {
            if isInsideExperimentalSandbox(parentDirectory) {
                allowed = true
                reason = "parent inside sandbox root"
            } else if grantService.hasGrant(containing: parentDirectory) {
                allowed = true
                reason = "parent inside explicit folder access grant"
            } else {
                allowed = false
                reason = "parent outside sandbox root and not explicitly granted"
            }
        } else {
            allowed = hasProcessAccess(to: parentDirectory, requireWritable: true) || grantService.hasGrant(containing: parentDirectory)
            reason = allowed ? "parent directly readable and writable, security-scoped, or granted" : "parent not writable or not authorized"
        }

        logDecision(allowed ? .debug : .warning, allowed: allowed, url: destination, reason: reason)
        guard allowed else {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied destination access validation: destination=\(DiagnosticLogger.sanitizedPath(destination)); parent=\(DiagnosticLogger.sanitizedPath(parentDirectory)); reason=\(reason)")
            throw isEnabled ? SandboxAccessError.outsideExperimentalSandbox(destination) : SandboxAccessError.unauthorized(destination)
        }
    }

    func validatedDirectory(_ url: URL, fallback: URL? = nil) -> URL {
        if canAccess(url) {
            return url
        }

        if let fallback, fallback != url, canAccess(fallback) {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Rejected denied directory and preserved fallback: requested=\(DiagnosticLogger.sanitizedPath(url)); fallback=\(DiagnosticLogger.sanitizedPath(fallback))")
            return fallback
        }

        if isEnabled, canAccess(rootURL) {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Redirected denied directory to sandbox root: requested=\(DiagnosticLogger.sanitizedPath(url))")
            return rootURL
        }

        DiagnosticLogger.log(.warning, category: "Sandbox", "Rejected denied directory with no accessible fallback: requested=\(DiagnosticLogger.sanitizedPath(url))")
        return fallback ?? url
    }

    #if canImport(AppKit)
    @MainActor
    func requestAccess(to directory: URL, window: NSWindow?, completion: @escaping (Bool) -> Void) {
        if isEnabled, canAccess(directory) {
            completion(true)
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
                completion(false)
                return
            }
            do {
                _ = try grantService.grantAccess(to: selectedURL)
                completion(true)
            } catch {
                completion(false)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
    #endif


    func withAccess<T>(to urls: [URL], _ body: () throws -> T) rethrows -> T {
        try grantService.withSecurityScopedAccess(to: urls, body)
    }

    func withAccess<T>(to urls: [URL], _ body: () async throws -> T) async rethrows -> T {
        try await grantService.withSecurityScopedAccess(to: urls, body)
    }

    func beginAccess(to urls: [URL]) -> FolderAccessScope {
        grantService.beginSecurityScopedAccess(to: urls)
    }

    func endAccess(_ scope: FolderAccessScope) {
        grantService.endSecurityScopedAccess(scope)
    }

    private func isInsideExperimentalSandbox(_ url: URL) -> Bool {
        let rootPath = normalizedPath(rootURL)
        let candidatePath = normalizedPath(url)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func hasProcessAccess(to url: URL, requireWritable: Bool = false) -> Bool {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let path = normalizedPath(url)
        guard accessProbe.fileExists(path), accessProbe.isReadableFile(path) else { return false }
        if requireWritable {
            return accessProbe.isWritableFile(path)
        }
        return true
    }

    private func logDecision(_ level: DiagnosticLogLevel, allowed: Bool, url: URL, reason: String) {
        DiagnosticLogger.log(level, category: "Sandbox", "\(allowed ? "Allowed" : "Denied") access decision: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

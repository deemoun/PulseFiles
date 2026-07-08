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
    private let isEnabledOverride: Bool?
    let rootURL: URL

    static let current = SandboxFileAccessPolicy(
        rootURL: ExperimentalFlags.appSandboxRoot
    )

    init(isEnabled: Bool? = nil, rootURL: URL) {
        self.isEnabledOverride = isEnabled
        self.rootURL = rootURL
    }

    var isEnabled: Bool {
        isEnabledOverride ?? ExperimentalFlags.restrictFileAccessToAppSandboxRoot
    }

    func canAccess(_ url: URL) -> Bool {
        let allowed: Bool
        let reason: String
        if isEnabled {
            allowed = isInsideExperimentalSandbox(url)
            reason = allowed ? "inside sandbox root" : "outside sandbox root"
        } else {
            allowed = hasProcessAccess(to: url)
            reason = allowed ? "directly readable or security-scoped" : "not readable or not authorized"
        }
        logDecision(allowed ? .debug : .warning, allowed: allowed, url: url, reason: reason)
        return allowed
    }

    func validateAccess(to url: URL) throws {
        guard canAccess(url) else {
            let reason = isEnabled ? "outside sandbox root" : "not readable or not authorized"
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied access validation: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
            throw isEnabled ? SandboxAccessError.outsideExperimentalSandbox(url) : SandboxAccessError.unauthorized(url)
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
        guard !isEnabled else {
            completion(canAccess(directory))
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
            completion(hasProcessAccess(to: selectedURL))
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
    #endif

    private func isInsideExperimentalSandbox(_ url: URL) -> Bool {
        let rootPath = normalizedPath(rootURL)
        let candidatePath = normalizedPath(url)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func hasProcessAccess(to url: URL) -> Bool {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        let path = normalizedPath(url)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return FileManager.default.isReadableFile(atPath: path)
        }

        return FileManager.default.isReadableFile(atPath: path)
    }

    private func logDecision(_ level: DiagnosticLogLevel, allowed: Bool, url: URL, reason: String) {
        DiagnosticLogger.log(level, category: "Sandbox", "\(allowed ? "Allowed" : "Denied") access decision: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

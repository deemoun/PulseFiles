import Foundation

enum SandboxAccessError: LocalizedError {
    case outsideExperimentalSandbox(URL)

    var errorDescription: String? {
        switch self {
        case .outsideExperimentalSandbox:
            return "Experimental sandbox mode is enabled.".localized
        }
    }

    var failureReason: String? {
        switch self {
        case .outsideExperimentalSandbox(let url):
            return "%@ is outside the PulseFiles experimental sandbox.".localized(with: url.path)
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
        guard isEnabled else {
            logDecision(.debug, allowed: true, url: url, reason: "sandbox restrictions disabled")
            return true
        }
        let rootPath = normalizedPath(rootURL)
        let candidatePath = normalizedPath(url)
        let allowed = candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
        logDecision(allowed ? .debug : .warning, allowed: allowed, url: url, reason: allowed ? "inside sandbox root" : "outside sandbox root")
        return allowed
    }

    func validatedDirectory(_ url: URL) -> URL {
        if canAccess(url) {
            return url
        }
        DiagnosticLogger.log(.warning, category: "Sandbox", "Redirected denied directory to sandbox root: requested=\(DiagnosticLogger.sanitizedPath(url))")
        return rootURL
    }

    func validateAccess(to url: URL) throws {
        guard canAccess(url) else {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied access validation: path=\(DiagnosticLogger.sanitizedPath(url)); reason=outside sandbox root")
            throw SandboxAccessError.outsideExperimentalSandbox(url)
        }
    }

    private func logDecision(_ level: DiagnosticLogLevel, allowed: Bool, url: URL, reason: String) {
        DiagnosticLogger.log(level, category: "Sandbox", "\(allowed ? "Allowed" : "Denied") access decision: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

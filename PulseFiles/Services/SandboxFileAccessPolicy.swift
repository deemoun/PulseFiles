import Foundation

enum SandboxAccessError: LocalizedError {
    case outsideExperimentalSandbox(URL)

    var errorDescription: String? {
        switch self {
        case .outsideExperimentalSandbox:
            return "Experimental sandbox mode is enabled."
        }
    }

    var failureReason: String? {
        switch self {
        case .outsideExperimentalSandbox(let url):
            return "\(url.path) is outside the PulseFiles experimental sandbox."
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
        guard isEnabled else { return true }
        let rootPath = normalizedPath(rootURL)
        let candidatePath = normalizedPath(url)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    func validatedDirectory(_ url: URL) -> URL {
        canAccess(url) ? url : rootURL
    }

    func validateAccess(to url: URL) throws {
        guard canAccess(url) else {
            throw SandboxAccessError.outsideExperimentalSandbox(url)
        }
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

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
    let isEnabled: Bool
    let rootURL: URL

    static let current = SandboxFileAccessPolicy(
        isEnabled: ExperimentalFlags.restrictFileAccessToAppSandboxRoot,
        rootURL: ExperimentalFlags.appSandboxRoot
    )

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

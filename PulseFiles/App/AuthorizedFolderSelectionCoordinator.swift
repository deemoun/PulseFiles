import AppKit

protocol FolderAccessGrantProviding: AnyObject {
    func grantAccess(to directory: URL) throws -> FolderAccessGrant
}

extension FolderAccessGrantService: FolderAccessGrantProviding {}

@MainActor
final class AuthorizedFolderSelectionCoordinator: AuthorizedFolderSelecting {
    typealias Request = FolderSelectionRequest
    typealias Failure = FolderSelectionFailure
    typealias Resolution = Result<URL, Failure>

    private let accessPolicy: SandboxFileAccessPolicy
    private let grantService: any FolderAccessGrantProviding
    var grantServiceForCompositionTesting: any FolderAccessGrantProviding { grantService }

    init(accessPolicy: SandboxFileAccessPolicy, grantService: any FolderAccessGrantProviding) {
        self.accessPolicy = accessPolicy
        self.grantService = grantService
    }

    func selectFolder(for request: Request, completion: @escaping (Resolution) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = request.prompt
        panel.message = request.message ?? ""
        panel.directoryURL = request.initialDirectory

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let selectedURL = panel?.url else {
                completion(.failure(.cancelled))
                return
            }
            guard let self else { return }
            completion(self.resolve(selectedURL: selectedURL, for: request))
        }
        if let window = request.presentingWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func presentFailure(_ failure: Failure, in window: NSWindow?) {
        FolderAccessFailurePresenter.present(failure, in: window)
    }

    func resolve(selectedURL: URL, for request: Request) -> Resolution {
        let normalizedURL = selectedURL.standardizedFileURL
        if request.acceptsExistingAccessibleURL {
            do {
                try accessPolicy.validateAccess(to: normalizedURL)
                return .success(normalizedURL)
            } catch {
                // A selection that is not already accessible may still become
                // authorized by a security-scoped bookmark below.
            }
        }

        let grantedURL: URL
        do {
            grantedURL = try grantService.grantAccess(to: normalizedURL).url.standardizedFileURL
        } catch {
            return .failure(.grant(error))
        }
        do {
            try accessPolicy.validateAccess(to: grantedURL)
            return .success(grantedURL)
        } catch {
            return .failure(.rejected(error))
        }
    }
}

@MainActor
enum FolderAccessFailurePresenter {
    static func present(_ failure: AuthorizedFolderSelectionCoordinator.Failure, in window: NSWindow?) {
        guard case .cancelled = failure else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Folder Access Needed".localized
            alert.informativeText = "PulseFiles does not currently have permission to access this folder. Choose another folder or grant access in macOS privacy settings.".localized
            alert.addButton(withTitle: "OK".localized)
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
    }
}

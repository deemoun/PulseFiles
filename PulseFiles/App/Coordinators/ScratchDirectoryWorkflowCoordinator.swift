import AppKit

/// Owns scratch-folder configuration, access recovery, and persisted selection.
/// The window supplies only presentation and navigation capabilities.
@MainActor
protocol ScratchDirectoryWorkflowPresenting: WorkflowWindowProviding, WorkflowAlertPresenting {
    func navigateToScratchDirectory(_ directory: URL, useInactive: Bool)
    func scratchDirectoryConfigurationDidChange()
}

@MainActor
final class ScratchDirectoryWorkflowCoordinator {
    private let settings: SettingsService
    private let accessPolicy: SandboxFileAccessPolicy
    private let folderSelection: AuthorizedFolderSelectionCoordinator
    private let cleanupFactory: (@escaping () -> [URL]) -> ScratchFolderCleanupService
    private let activeRoots: () -> [URL]
    private let router = ScratchDirectoryCommandRouter()

    init(
        settings: SettingsService,
        accessPolicy: SandboxFileAccessPolicy,
        folderSelection: AuthorizedFolderSelectionCoordinator,
        cleanupFactory: @escaping (@escaping () -> [URL]) -> ScratchFolderCleanupService,
        activeRoots: @escaping () -> [URL]
    ) {
        self.settings = settings
        self.accessPolicy = accessPolicy
        self.folderSelection = folderSelection
        self.cleanupFactory = cleanupFactory
        self.activeRoots = activeRoots
    }

    func perform(useInactive: Bool, presenter: any ScratchDirectoryWorkflowPresenting) {
        switch router.route(configuredDirectory: settings.scratchDirectory, canAccess: { self.accessPolicy.canAccess($0) }) {
        case .promptForConfiguration:
            confirmConfiguration(useInactive: useInactive, presenter: presenter)
        case .requestAccess(let directory):
            recoverAccess(to: directory, useInactive: useInactive, presenter: presenter)
        case .navigate(let directory):
            presenter.navigateToScratchDirectory(directory, useInactive: useInactive)
        case .cancelled:
            break
        }
    }

    private func confirmConfiguration(useInactive: Bool, presenter: any ScratchDirectoryWorkflowPresenting) {
        let alert = NSAlert()
        alert.messageText = "No Scratch Folder Configured".localized
        alert.informativeText = "Choose a folder to use as your scratch workspace.".localized
        alert.addButton(withTitle: "Choose Folder…".localized)
        alert.addButton(withTitle: "Cancel".localized)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak presenter] response in
            guard response == .alertFirstButtonReturn, let self, let presenter else { return }
            self.chooseDirectory(useInactive: useInactive, presenter: presenter)
        }
        if let window = presenter.workflowWindow { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }

    private func recoverAccess(to directory: URL, useInactive: Bool, presenter: any ScratchDirectoryWorkflowPresenting) {
        let request = AuthorizedFolderSelectionCoordinator.Request(
            prompt: "Grant Access".localized,
            message: "Choose a folder containing the configured scratch folder.".localized,
            initialDirectory: directory,
            acceptsExistingAccessibleURL: true,
            presentingWindow: presenter.workflowWindow
        )
        folderSelection.selectFolder(for: request) { [weak self, weak presenter] result in
            guard let self, let presenter else { return }
            let granted = result.isSuccess && self.accessPolicy.canAccess(directory)
            if case .navigate(let recovered) = self.router.routeAfterAccessRecovery(to: directory, wasGranted: granted) {
                presenter.navigateToScratchDirectory(recovered, useInactive: useInactive)
            }
            if case .failure(let failure) = result {
                FolderAccessFailurePresenter.present(failure, in: presenter.workflowWindow)
            }
        }
    }

    private func chooseDirectory(useInactive: Bool, presenter: any ScratchDirectoryWorkflowPresenting) {
        let request = AuthorizedFolderSelectionCoordinator.Request(prompt: "Choose".localized, presentingWindow: presenter.workflowWindow)
        folderSelection.selectFolder(for: request) { [weak self, weak presenter] result in
            guard let self, let presenter else { return }
            guard case .success(let directory) = result else {
                if case .failure(let failure) = result { FolderAccessFailurePresenter.present(failure, in: presenter.workflowWindow) }
                return
            }
            do {
                let selection = try self.cleanupFactory(self.activeRoots).captureSelection(for: directory)
                self.settings.scratchDirectory = selection.directory
                self.settings.scratchFolderSelection = selection
                presenter.navigateToScratchDirectory(selection.directory, useInactive: useInactive)
                presenter.scratchDirectoryConfigurationDidChange()
            } catch {
                presenter.workflowFailed(message: "Could Not Configure Scratch Folder".localized, detail: error.localizedDescription)
            }
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

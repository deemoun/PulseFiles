import AppKit

@MainActor
struct MainWindowWorkflowDependencies {
    let fileTransfer: FileTransferWorkflowCoordinator
    let fileCreation: FileCreationWorkflowCoordinator
    let search: SearchWorkflowCoordinator
    let auxiliaryPanels: AuxiliaryPresentationCoordinator
    let archiveAndRename: ArchiveAndRenameWorkflowCoordinator
    let openWith: OpenWithWorkflowCoordinator
    let goToFolder: GoToFolderWorkflowCoordinator
    let commandPresentation: CommandPresentationCoordinator
    let paneSynchronization: PaneNavigationSynchronizationCoordinator

    static func production(from dependencies: MainWindowDependencies, accessPolicy: SandboxFileAccessPolicy) -> Self {
        Self(
            fileTransfer: .init(fileOperations: dependencies.fileOperations, clipboard: dependencies.clipboard, accessPolicy: accessPolicy),
            fileCreation: .init(fileOperations: dependencies.fileOperations, accessPolicy: accessPolicy),
            search: .init(service: dependencies.descendantSearch, accessPolicy: accessPolicy),
            auxiliaryPanels: .init(),
            archiveAndRename: .init(fileOperations: dependencies.fileOperations),
            openWith: .init(accessPolicy: accessPolicy),
            goToFolder: .init(probe: dependencies.fileSystemProbe, accessPolicy: accessPolicy),
            commandPresentation: .init(),
            paneSynchronization: .init()
        )
    }
}

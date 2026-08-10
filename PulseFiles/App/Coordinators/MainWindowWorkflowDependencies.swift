import AppKit

@MainActor
struct MainWindowWorkflowDependencies {
    let fileTransfer: FileTransferWorkflowCoordinator
    let fileCreation: FileCreationWorkflowCoordinator
    let search: SearchWorkflowCoordinator
    let auxiliaryPanels: AuxiliaryPanelCoordinator
    let archiveAndRename: ArchiveAndRenameWorkflowCoordinator
    let openWith: OpenWithWorkflowCoordinator
    let goToFolder: GoToFolderWorkflowCoordinator

    static func production(from dependencies: MainWindowDependencies, accessPolicy: SandboxFileAccessPolicy) -> Self {
        Self(
            fileTransfer: .init(fileOperations: dependencies.fileOperations, clipboard: dependencies.clipboard, accessPolicy: accessPolicy),
            fileCreation: .init(fileOperations: dependencies.fileOperations, accessPolicy: accessPolicy),
            search: .init(service: dependencies.descendantSearch, accessPolicy: accessPolicy),
            auxiliaryPanels: .init(),
            archiveAndRename: .init(fileOperations: dependencies.fileOperations),
            openWith: .init(accessPolicy: accessPolicy),
            goToFolder: .init(probe: dependencies.fileSystemProbe, accessPolicy: accessPolicy)
        )
    }
}

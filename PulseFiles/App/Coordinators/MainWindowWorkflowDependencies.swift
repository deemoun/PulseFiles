import AppKit

@MainActor
struct MainWindowWorkflowDependencies {
    let fileTransfer: FileTransferWorkflowCoordinator
    let fileCreation: FileCreationWorkflowCoordinator
    let search: SearchWorkflowCoordinator
    let auxiliaryPanels: AuxiliaryPanelCoordinator

    static func production(from dependencies: MainWindowDependencies, accessPolicy: SandboxFileAccessPolicy) -> Self {
        Self(
            fileTransfer: .init(fileOperations: dependencies.fileOperations, clipboard: dependencies.clipboard, accessPolicy: accessPolicy),
            fileCreation: .init(fileOperations: dependencies.fileOperations, accessPolicy: accessPolicy),
            search: .init(service: dependencies.descendantSearch, accessPolicy: accessPolicy),
            auxiliaryPanels: .init()
        )
    }
}

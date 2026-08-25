import AppKit
import Foundation
import UniformTypeIdentifiers

/// Owns archive and multi-item rename dialogs and translates their answers into
/// service requests. Pane selection remains a responsibility of the caller.
@MainActor
final class ArchiveAndRenameWorkflowCoordinator {
    private let fileOperations: any FileOperationCoordinating

    init(fileOperations: any FileOperationCoordinating) { self.fileOperations = fileOperations }

    func promptForArchiveCreation(sources: [URL], directory: URL, presenter: any WorkflowWindowProviding & WorkflowAlertPresenting & WorkflowOperationExecuting & WorkflowConflictResolving) {
        guard !sources.isEmpty else { NSSound.beep(); return }
        let panel = NSSavePanel(); panel.title = "Create Archive".localized; panel.nameFieldStringValue = "Archive.zip".localized
        panel.directoryURL = directory; panel.allowedContentTypes = [.zip]
        present(panel, window: presenter.workflowWindow) { [fileOperations] destination in
            let request = ArchiveCreateRequest(sources: sources, destinationURL: destination)
            presenter.startWorkflowOperation(named: "Create Archive".localized) { progress in
                try await fileOperations.createArchive(request, progressHandler: progress)
            }
        }
    }

    func confirmArchiveExtraction(archive: URL?, directory: URL, presenter: any WorkflowWindowProviding & WorkflowAlertPresenting & WorkflowOperationExecuting & WorkflowConflictResolving) {
        guard let archive else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "Extract Archive?".localized
        alert.informativeText = "Archive entries will be safety-checked and extracted into the current folder. Existing items require a conflict decision.".localized
        alert.addButton(withTitle: "Extract".localized); alert.addButton(withTitle: "Cancel".localized)
        present(alert, window: presenter.workflowWindow) { [fileOperations] in
            let request = ArchiveExtractRequest(archiveURL: archive, destinationDirectory: directory)
            presenter.startWorkflowOperation(named: "Extract Archive".localized) { progress in
                try await fileOperations.extractArchive(request, conflictHandler: { destination in
                    await presenter.resolveWorkflowConflict(destination: destination, operationName: "Extract Archive".localized)
                }, progressHandler: progress)
            }
        }
    }

    func promptForBatchRename(sources: [URL], presenter: any WorkflowWindowProviding & WorkflowAlertPresenting & WorkflowOperationExecuting & WorkflowConflictResolving) {
        guard !sources.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = "Batch Rename".localized
        alert.informativeText = "Enter a base name. PulseFiles will preview every destination before changing files.".localized
        let field = NSTextField(string: "Item"); field.frame.size.width = 320; alert.accessoryView = field
        alert.addButton(withTitle: "Preview".localized); alert.addButton(withTitle: "Cancel".localized)
        present(alert, window: presenter.workflowWindow) { [fileOperations] in
            let names = Self.proposedNames(for: sources, baseName: field.stringValue)
            do {
                let plan = try fileOperations.planBatchRename(.init(sources: sources, proposedNames: names))
                let confirmation = NSAlert(); confirmation.messageText = "Confirm Batch Rename".localized
                confirmation.informativeText = plan.items.map { "\($0.sourceURL.lastPathComponent) → \($0.destinationURL.lastPathComponent)" }.joined(separator: "\n")
                confirmation.addButton(withTitle: "Rename All".localized); confirmation.addButton(withTitle: "Cancel".localized)
                self.present(confirmation, window: presenter.workflowWindow) {
                    presenter.startWorkflowOperation(named: "Batch Rename".localized) { progress in
                        await fileOperations.batchRename(plan, progressHandler: progress)
                    }
                }
            } catch { presenter.workflowFailed(message: "Could Not Plan Batch Rename".localized, detail: error.localizedDescription) }
        }
    }

    nonisolated static func proposedNames(for sources: [URL], baseName: String) -> [String] {
        sources.enumerated().map { index, source in
            let suffix = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
            return "\(baseName) \(index + 1)\(suffix)"
        }
    }

    private func present(_ alert: NSAlert, window: NSWindow?, accepted: @escaping () -> Void) {
        let completion: (NSApplication.ModalResponse) -> Void = { if $0 == .alertFirstButtonReturn { accepted() } }
        if let window { alert.beginSheetModal(for: window, completionHandler: completion) } else { completion(alert.runModal()) }
    }

    private func present(_ panel: NSSavePanel, window: NSWindow?, accepted: @escaping (URL) -> Void) {
        let completion: (NSApplication.ModalResponse) -> Void = { [weak panel] response in if response == .OK, let url = panel?.url { accepted(url) } }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) } else { completion(panel.runModal()) }
    }
}

import AppKit
import Foundation

@MainActor
final class FileCreationWorkflowCoordinator {
    private let fileOperations: any FileOperationCoordinating
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileOperations: any FileOperationCoordinating, accessPolicy: SandboxFileAccessPolicy) {
        self.fileOperations = fileOperations
        self.accessPolicy = accessPolicy
    }

    func createFolder(named name: String, in directory: URL) async throws -> FileOperationResult {
        try await fileOperations.createFolder(named: name, in: directory)
    }

    func createFile(named name: String, in directory: URL) async throws -> FileOperationResult {
        try await fileOperations.createFile(named: name, in: directory)
    }

    func promptForFolder(in directory: URL, window: NSWindow?, submit: @escaping (String, URL) -> Void) {
        prompt(title: "New Folder".localized, detail: "Create a folder in %@".localized(with: directory.path),
               defaultName: "Untitled Folder", directory: directory, isDirectory: true, window: window, submit: submit)
    }

    func promptForFile(in directory: URL, window: NSWindow?, submit: @escaping (String, URL) -> Void) {
        prompt(title: "New File".localized, detail: "Create a file in %@".localized(with: directory.path),
               defaultName: "Untitled.txt", directory: directory, isDirectory: false, window: window, submit: submit)
    }

    private func prompt(title: String, detail: String, defaultName: String, directory: URL, isDirectory: Bool,
                        window: NSWindow?, submit: @escaping (String, URL) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Create".localized); alert.addButton(withTitle: "Cancel".localized)
        let field = NSTextField(string: defaultName); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field
        Task { [weak field] in
            let suggestion = await suggestedName(in: directory, base: defaultName, isDirectory: isDirectory)
            if field?.stringValue == defaultName { field?.stringValue = suggestion }
        }
        let response: (NSApplication.ModalResponse) -> Void = { if $0 == .alertFirstButtonReturn { submit(field.stringValue, directory) } }
        if let window { alert.beginSheetModal(for: window, completionHandler: response) } else { response(alert.runModal()) }
    }

    func suggestedName(in directory: URL, base: String, isDirectory: Bool) async -> String {
        await Self.uniqueName(in: directory, base: base, isDirectory: isDirectory, accessPolicy: accessPolicy)
    }

    /// Advisory naming only. FileOperationService remains the authority for collisions.
    nonisolated static func uniqueName(in directory: URL, base: String, isDirectory: Bool, accessPolicy: SandboxFileAccessPolicy) async -> String {
        await Task.detached(priority: .utility) {
            (try? accessPolicy.withValidatedAccess(to: directory) {
                let suffix = isDirectory ? "" : ".txt"
                let stem = isDirectory ? base : "Untitled"
                for index in 1...10_000 {
                    if Task.isCancelled { return base }
                    let candidate = index == 1 ? base : "\(stem) \(index)\(suffix)"
                    if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate, isDirectory: isDirectory).path) {
                        return candidate
                    }
                }
                return "\(stem) \(UUID().uuidString)\(suffix)"
            }) ?? base
        }.value
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol WorkflowWindowProviding: AnyObject {
    var workflowWindow: NSWindow? { get }
}

@MainActor
protocol WorkflowAlertPresenting: AnyObject {
    func workflowFailed(message: String, detail: String)
}

@MainActor
protocol WorkflowOperationExecuting: AnyObject {
    func startWorkflowOperation(named name: String, operation: @escaping (FileOperationProgressHandler?) async throws -> FileOperationResult)
}

@MainActor
protocol WorkflowConflictResolving: AnyObject {
    func resolveWorkflowConflict(destination: URL, operationName: String) async -> FileConflictResolution
}


@MainActor
final class OpenWithWorkflowCoordinator {
    private let accessPolicy: SandboxFileAccessPolicy
    init(accessPolicy: SandboxFileAccessPolicy) { self.accessPolicy = accessPolicy }

    func present(files: [URL], presenter: any WorkflowWindowProviding & WorkflowAlertPresenting, open: @escaping (URL, URL) -> Void) {
        guard !files.isEmpty else { presenter.workflowFailed(message: "Nothing Selected".localized, detail: "Select one or more files to open with another application.".localized); return }
        do {
            for file in files where try !accessPolicy.withValidatedAccess(to: file, { FileManager.default.fileExists(atPath: file.path) }) {
                throw FileOperationError.sourceMissing(file)
            }
        } catch { presenter.workflowFailed(message: "Could Not Open File".localized, detail: error.localizedDescription); return }
        let panel = NSOpenPanel(); panel.title = "Open With…".localized; panel.prompt = "Open".localized
        panel.message = files.count == 1 ? "Choose an application to open %@.".localized(with: files[0].lastPathComponent) : "Choose an application to open the selected files.".localized
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true); panel.canChooseFiles = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.applicationBundle]
        let completion: (NSApplication.ModalResponse) -> Void = { [weak panel] response in
            guard response == .OK, let application = panel?.url else { return }; files.forEach { open($0, application) }
        }
        if let window = presenter.workflowWindow { panel.beginSheetModal(for: window, completionHandler: completion) } else { completion(panel.runModal()) }
    }
}

@MainActor
final class GoToFolderWorkflowCoordinator {
    private let probe: any FileSystemProbing
    private let accessPolicy: SandboxFileAccessPolicy
    private var generation = 0
    init(probe: any FileSystemProbing, accessPolicy: SandboxFileAccessPolicy) { self.probe = probe; self.accessPolicy = accessPolicy }

    func prompt(currentDirectory: URL, presenter: any WorkflowWindowProviding & WorkflowAlertPresenting, resolved: @escaping (URL) -> Void) {
        let alert = NSAlert(); alert.messageText = "Go to Folder".localized
        alert.informativeText = "Enter an absolute, home-relative, or active-pane-relative folder path. If macOS denies access, open or grant the folder first.".localized
        alert.addButton(withTitle: "Go".localized); alert.addButton(withTitle: "Cancel".localized)
        let field = NSTextField(string: currentDirectory.path); field.frame = NSRect(x: 0, y: 0, width: 420, height: 24); alert.accessoryView = field
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }; self?.resolve(field.stringValue, relativeTo: currentDirectory, presenter: presenter, completion: resolved)
        }
        if let window = presenter.workflowWindow { alert.beginSheetModal(for: window, completionHandler: completion) } else { completion(alert.runModal()) }
    }

    func resolve(_ rawPath: String, relativeTo directory: URL, presenter: any WorkflowWindowProviding & WorkflowAlertPresenting, completion: @escaping (URL) -> Void) {
        generation += 1; let requestGeneration = generation
        Task { [probe, accessPolicy] in
            do {
                let url = try await Self.resolvePath(rawPath, relativeTo: directory, probe: probe, accessPolicy: accessPolicy)
                guard requestGeneration == generation else { return }; completion(url)
            } catch is CancellationError {} catch {
                guard requestGeneration == generation else { return }; presenter.workflowFailed(message: "Could Not Go to Folder".localized, detail: error.localizedDescription)
            }
        }
    }

    nonisolated static func resolvePath(_ rawPath: String, relativeTo directory: URL, probe: any FileSystemProbing, accessPolicy: SandboxFileAccessPolicy) async throws -> URL {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines); guard !path.isEmpty else { throw FileNameValidator.ValidationError.empty }
        let expanded = path == "~" ? FileManager.default.homeDirectoryForCurrentUser.path
            : path.hasPrefix("~/") ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2))).path
            : path.hasPrefix("/") ? path : directory.appendingPathComponent(path).path
        let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let answer = try await accessPolicy.withValidatedAccess(to: url) { await probe.isDirectory(url, deadline: .milliseconds(250)) }
        guard case .value(let isDirectory) = answer else { throw FileOperationError.destinationDirectoryMissing(url) }
        guard isDirectory else { throw FileOperationError.destinationNotDirectory(url) }; return url
    }
}

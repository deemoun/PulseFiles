// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesModels
import PulseFilesServices
import PulseFilesUtilities

/// Owns bounded operation-summary collection and the complete diagnostics
/// destination/export/reveal presentation flow.
@MainActor
final class DiagnosticsWorkflow {
    private let exporter: any DiagnosticsExporting
    private let folderSelection: AuthorizedFolderSelectionCoordinator
    private let entries: @MainActor () -> [DiagnosticLogEntry]
    private let reveal: ([URL]) -> Void
    private let showError: (String, String) -> Void
    private var operationSummaries: [DiagnosticOperationSummary] = []

    init(
        exporter: any DiagnosticsExporting,
        folderSelection: AuthorizedFolderSelectionCoordinator,
        entries: @escaping @MainActor () -> [DiagnosticLogEntry] = { DiagnosticLogService.shared.entries },
        reveal: @escaping ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) },
        showError: @escaping (String, String) -> Void
    ) {
        self.exporter = exporter
        self.folderSelection = folderSelection
        self.entries = entries
        self.reveal = reveal
        self.showError = showError
    }

    func record(operation: String, result: FileOperationResult) {
        operationSummaries.append(.init(operation: operation, result: result))
        if operationSummaries.count > 20 { operationSummaries.removeFirst(operationSummaries.count - 20) }
    }

    func presentExport(in window: NSWindow?) {
        let request = AuthorizedFolderSelectionCoordinator.Request(
            prompt: "Export".localized,
            message: "Choose a folder for a local support bundle. Review it before attaching it to a support request.".localized,
            acceptsExistingAccessibleURL: true,
            presentingWindow: window
        )
        folderSelection.selectFolder(for: request) { [weak self] result in
            guard let self else { return }
            guard case let .success(destination) = result else {
                if case let .failure(failure) = result { FolderAccessFailurePresenter.present(failure, in: window) }
                return
            }
            do {
                let bundle = try exporter.export(to: destination, entries: entries(), operationSummaries: operationSummaries)
                reveal([bundle])
            } catch {
                showError("Could Not Export Diagnostics".localized, error.localizedDescription)
            }
        }
    }

    var summaryCountForTesting: Int { operationSummaries.count }
}

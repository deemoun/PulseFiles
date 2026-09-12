// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class FileOperationUIAdapter {
    private let presentation: FileOperationPresentationCoordinator
    private let progress: FileOperationProgressWindowController
    private let window: () -> NSWindow?
    private let probe: any FileSystemProbing
    private let showError: (String, String) -> Void
    private var previousTitle: String?

    init(presentation: FileOperationPresentationCoordinator, progress: FileOperationProgressWindowController, probe: any FileSystemProbing, window: @escaping () -> NSWindow?, showError: @escaping (String, String) -> Void) {
        self.presentation = presentation
        self.progress = progress
        self.probe = probe
        self.window = window
        self.showError = showError
    }

    func confirm(operationName: String, urls: [URL], destination: URL?, buttonTitle: String, completion: @escaping () -> Void) {
        let alert = presentation.confirmation(operationName: operationName, urls: urls, destinationDirectory: destination, confirmButtonTitle: buttonTitle).makeAlert()
        let response: (NSApplication.ModalResponse) -> Void = { value in
            guard value == .alertFirstButtonReturn else { return }
            completion()
        }
        if let window = window() { alert.beginSheetModal(for: window, completionHandler: response) }
        else { response(alert.runModal()) }
    }

    func beginProgress(named name: String) {
        previousTitle = window()?.title
        progress.show(operationName: name, parentWindow: window())
    }

    func update(_ value: FileOperationProgress, operationName: String) {
        progress.update(operationName: operationName, progress: value)
        window()?.title = "\(operationName): \(value.currentItemName)"
    }

    func endProgress() {
        if let previousTitle { window()?.title = previousTitle }
        previousTitle = nil
        progress.dismiss()
    }

    func showCancellationPending() { progress.showCancellationPending() }

    func resolveConflict(destination: URL, operationName: String) async -> FileConflictResolution {
        guard let keepBoth = await FileSystemProbeDecisionCoordinator(probe: probe).keepBothDestination(for: destination) else {
            showError("Could Not Verify Conflict".localized, "The destination could not be checked in time. The operation was cancelled without replacing anything.".localized)
            return .cancel
        }
        let conflict = presentation.conflict(destination: destination, operationName: operationName, keepBothDestination: keepBoth)
        let alert = conflict.0.makeAlert()
        let applyToRemaining = NSButton(checkboxWithTitle: "Apply this choice to remaining conflicts".localized, target: nil, action: nil)
        applyToRemaining.setAccessibilityLabel("Apply this conflict choice to remaining conflicts".localized)
        alert.accessoryView = applyToRemaining
        guard let window = window() else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                let apply = applyToRemaining.state == .on
                switch response {
                case .alertFirstButtonReturn: continuation.resume(returning: apply ? .applyToRemainingKeepBoth : .keepBoth)
                case .alertSecondButtonReturn: continuation.resume(returning: apply ? .applyToRemainingReplace : .replace)
                case .alertThirdButtonReturn: continuation.resume(returning: apply ? .applyToRemainingSkip : .skip)
                default: continuation.resume(returning: .cancel)
                }
            }
        }
    }
}

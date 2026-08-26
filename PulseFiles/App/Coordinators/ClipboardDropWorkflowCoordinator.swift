// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Owns the pasteboard session, including transient feedback and cut markers.
@MainActor
final class ClipboardDropWorkflowCoordinator {
    private let transfer: FileTransferWorkflowCoordinator
    private let onCutURLsChanged: ([URL]) -> Void
    private let onFeedbackExpired: () -> Void
    private var feedbackTimer: Timer?
    private var changeMonitor: Timer?
    private var trackedChangeCount: Int?
    private(set) var cutURLs: Set<URL> = []

    init(
        transfer: FileTransferWorkflowCoordinator,
        onCutURLsChanged: @escaping ([URL]) -> Void,
        onFeedbackExpired: @escaping () -> Void
    ) {
        self.transfer = transfer
        self.onCutURLsChanged = onCutURLsChanged
        self.onFeedbackExpired = onFeedbackExpired
    }
    func payload() -> FileClipboard.Payload? { transfer.clipboardPayload() }
    func write(_ urls: [URL], operation: FileClipboard.Operation) throws {
        try transfer.writeToClipboard(urls, operation: operation)
        cutURLs = operation == .move ? Set(urls) : []
        onCutURLsChanged(operation == .move ? urls : [])
        trackedChangeCount = transfer.clipboard.changeCount
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onFeedbackExpired() }
        }
        changeMonitor?.invalidate()
        changeMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let trackedChangeCount,
                      transfer.clipboard.changeCount != trackedChangeCount else { return }
                self.clear()
                self.onFeedbackExpired()
            }
        }
    }
    func clear() {
        feedbackTimer?.invalidate(); feedbackTimer = nil
        changeMonitor?.invalidate(); changeMonitor = nil
        trackedChangeCount = nil; cutURLs = []
        onCutURLsChanged([])
    }

    func validateDrop(sources: [URL], destination: URL, probe: any FileSystemProbing) async throws -> Int {
        try await transfer.validateDrop(sources: sources, destination: destination, probe: probe)
    }

    func isCurrentDrop(generation: Int) -> Bool { transfer.isCurrentDrop(generation: generation) }
}

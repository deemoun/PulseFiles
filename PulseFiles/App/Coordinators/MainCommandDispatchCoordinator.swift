// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Narrow seams used by the window workflow coordinators. They intentionally
/// expose no view-controller concrete types and no filesystem mutation API.
@MainActor
protocol MainWindowAlertPresenting: AnyObject {
    func presentAlert(message: String, detail: String, style: NSAlert.Style)
}

@MainActor
protocol MainWindowPaneAccessing: AnyObject {
    func currentDirectory(for pane: PaneID) -> URL
    func selectedURLs(for pane: PaneID) -> [URL]
    func refresh(_ pane: PaneID)
}

@MainActor
protocol FileOperationProgressPresenting: AnyObject {
    func show(operationName: String)
    func update(operationName: String, progress: FileOperationProgress)
    func showCancellationPending()
    func dismiss()
}

@MainActor
protocol MainWindowSettingsUpdating: AnyObject {
    func setSidebarVisible(_ visible: Bool)
    func setTerminalVisible(_ visible: Bool)
    func setSidebarWidth(_ width: Double)
}

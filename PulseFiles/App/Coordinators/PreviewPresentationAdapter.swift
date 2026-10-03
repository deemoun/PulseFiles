// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Quartz
import PulseFilesServices
import PulseFilesUtilities

/// Owns Quick Look probe state and read-only viewer window presentation. Its
/// inputs are values and closures, never pane controllers.
@MainActor
final class PreviewPresentationAdapter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    enum Request: Equatable {
        case quickLook(url: URL)
        case viewer(url: URL, isDirectory: Bool)
    }

    private let preview: PreviewCoordinator
    private let viewerService: any ViewerContentLoading
    private let showError: (String, String) -> Void
    private var probeGeneration = 0
    private(set) var quickLookPreviewURL: NSURL?
    private var viewerWindows: [NSWindowController] = []

    init(preview: PreviewCoordinator, viewerService: any ViewerContentLoading, showError: @escaping (String, String) -> Void) {
        self.preview = preview
        self.viewerService = viewerService
        self.showError = showError
    }

    func present(_ request: Request, isStillFocused: @escaping (URL) -> Bool = { _ in true }) {
        switch request {
        case let .quickLook(url): presentQuickLook(url, isStillFocused: isStillFocused)
        case let .viewer(url, isDirectory):
            guard !isDirectory else {
                showError("Nothing Selected".localized, "Select a file to view.".localized)
                return
            }
            presentViewer(url)
        }
    }

    private func presentQuickLook(_ url: URL, isStillFocused: @escaping (URL) -> Bool) {
        probeGeneration += 1
        let generation = probeGeneration
        Task { [weak self] in
            guard let self else { return }
            let availability = await preview.availability(of: url)
            guard generation == probeGeneration, isStillFocused(url) else { return }
            if case let .blocked(detail) = availability {
                showError("Preview Blocked".localized, detail)
                return
            }
            guard availability == .available else {
                showError("Preview Unavailable".localized, "The selected item is unavailable or no longer exists.".localized)
                return
            }
            quickLookPreviewURL = url as NSURL
            guard let panel = QLPreviewPanel.shared() else {
                showError("Preview Unavailable".localized, "Quick Look is not available for this item.".localized)
                return
            }
            connect(panel)
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func presentViewer(_ url: URL) {
        let viewer = FileViewerViewController(url: url, service: viewerService)
        let window = NSWindow(contentViewController: viewer)
        window.title = url.lastPathComponent
        window.setContentSize(NSSize(width: 820, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let controller = NSWindowController(window: window)
        viewerWindows.removeAll { $0.window == nil }
        viewerWindows.append(controller)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func connect(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func disconnect(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { quickLookPreviewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { quickLookPreviewURL }

    var retainedViewerWindowCountForTesting: Int {
        viewerWindows.removeAll { $0.window == nil }
        return viewerWindows.count
    }
}

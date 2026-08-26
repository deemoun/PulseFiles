// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesUtilities

/// Keeps the pane's volume status responsive while volume resource values are read.
/// A result is accepted only for the directory and directory-load generation that
/// initiated it, preventing a slow previous volume from replacing current status.
@MainActor
package final class VolumeStatusResolutionCache {
    private struct Request: Equatable {
        let directory: URL
        let loadGeneration: Int
    }

    private var task: Task<Void, Never>?
    private var request: Request?
    package private(set) var status: VolumeStatusPresentation
    package var onChange: (() -> Void)?

    package init(directory: URL) {
        status = .loading(for: directory)
    }

    deinit {
        task?.cancel()
    }

    package func resolveIfNeeded(for directory: URL, loadGeneration: Int) {
        let request = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        guard request != self.request else { return }
        beginResolution(for: directory, loadGeneration: loadGeneration)
        task = Task { [weak self] in
            let status = await VolumeStatusPresentation.resolve(for: directory)
            guard !Task.isCancelled else { return }
            self?.apply(status, for: directory, loadGeneration: loadGeneration)
        }
    }

    package func beginResolution(for directory: URL, loadGeneration: Int) {
        task?.cancel()
        self.request = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        status = .loading(for: directory)
        onChange?()
    }

    /// Kept internal so XCTest can verify stale-result suppression without relying
    /// on timing-sensitive filesystem behavior.
    package func apply(_ status: VolumeStatusPresentation, for directory: URL, loadGeneration: Int) {
        let completedRequest = Request(directory: directory.standardizedFileURL, loadGeneration: loadGeneration)
        guard completedRequest == request else { return }
        self.status = status
        task = nil
        onChange?()
    }
}

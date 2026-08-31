// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Owns cross-pane navigation decisions and invalidates stale asynchronous volume probes.
@MainActor
package final class PaneNavigationSynchronizationCoordinator {
    package struct RevealPlan: Equatable { package let directory: URL; package let item: URL }
    package init() {}

    private var volumeProbeGeneration = 0

    package func synchronizedDirectory(from source: URL) -> URL { source }
    package func revealPlan(for item: URL) -> RevealPlan { .init(directory: item.deletingLastPathComponent(), item: item) }
    package func beginVolumeProbe() -> Int { volumeProbeGeneration += 1; return volumeProbeGeneration }
    package func acceptsVolumeProbe(_ generation: Int, originalDirectories: [URL], currentDirectories: [URL]) -> Bool {
        generation == volumeProbeGeneration && originalDirectories == currentDirectories
    }
}

import Foundation

/// Owns cross-pane navigation decisions and invalidates stale asynchronous volume probes.
@MainActor
final class PaneNavigationSynchronizationCoordinator {
    struct RevealPlan: Equatable { let directory: URL; let item: URL }
    private var volumeProbeGeneration = 0

    func synchronizedDirectory(from source: URL) -> URL { source }
    func revealPlan(for item: URL) -> RevealPlan { .init(directory: item.deletingLastPathComponent(), item: item) }
    func beginVolumeProbe() -> Int { volumeProbeGeneration += 1; return volumeProbeGeneration }
    func acceptsVolumeProbe(_ generation: Int, originalDirectories: [URL], currentDirectories: [URL]) -> Bool {
        generation == volumeProbeGeneration && originalDirectories == currentDirectories
    }
}

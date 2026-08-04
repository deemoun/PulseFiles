import Foundation

struct SidebarNavigationSection {
    let title: String
    let items: [SidebarItem]
}

@MainActor
final class SelectionInspectorViewModel {
    private(set) var generation = 0
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    @discardableResult
    func beginSelection() -> Int {
        generation += 1
        task?.cancel()
        task = nil
        return generation
    }

    func isCurrent(_ candidate: Int) -> Bool {
        candidate == generation && task?.isCancelled != true
    }

    func run(_ operation: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { await operation() }
    }
}

@MainActor
final class SidebarNavigationModel {
    private let volumeDiscovery: any VolumeDiscovering
    private(set) var volumes: [Volume] = []
    private(set) var generation = 0
    private var task: Task<Void, Never>?

    init(volumeDiscovery: any VolumeDiscovering) {
        self.volumeDiscovery = volumeDiscovery
    }

    deinit { task?.cancel() }

    func sections(scratch: [SidebarItem], workspace: [SidebarItem], favorites: [SidebarItem], devices: [SidebarItem], recent: [SidebarItem], isRestricted: Bool) -> [SidebarNavigationSection] {
        let candidates = isRestricted
            ? [("Temporary Workspace".localized, scratch), ("Workspace", workspace), ("Recent", recent)]
            : [("Temporary Workspace".localized, scratch), ("Favorites", favorites), ("Devices", devices), ("Recent", recent)]
        return candidates.compactMap { title, items in
            items.isEmpty ? nil : SidebarNavigationSection(title: title, items: items)
        }
    }

    func refresh(onChange: @escaping @MainActor () -> Void) {
        generation += 1
        let requestedGeneration = generation
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let discovered = await volumeDiscovery.mountedVolumes()
            guard !Task.isCancelled, generation == requestedGeneration else { return }
            volumes = discovered
            onChange()
        }
    }
}

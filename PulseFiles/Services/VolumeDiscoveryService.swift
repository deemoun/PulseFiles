import AppKit
import Foundation

/// A mounted filesystem that can be presented in the sidebar without granting access to it.
struct Volume: Equatable, Sendable {
  let url: URL
  let displayName: String
  let isRemovable: Bool
  let isLocal: Bool
  let isNetwork: Bool
  let isReadOnly: Bool
  let totalCapacity: Int64?
  let availableCapacity: Int64?

  init(
    url: URL,
    displayName: String,
    isRemovable: Bool,
    isLocal: Bool,
    isNetwork: Bool,
    isReadOnly: Bool,
    totalCapacity: Int64? = nil,
    availableCapacity: Int64? = nil
  ) {
    self.url = url
    self.displayName = displayName
    self.isRemovable = isRemovable
    self.isLocal = isLocal
    self.isNetwork = isNetwork
    self.isReadOnly = isReadOnly
    self.totalCapacity = totalCapacity
    self.availableCapacity = availableCapacity
  }
}

protocol VolumeDiscovering {
  /// Returns the currently mounted volumes without requiring callers to block
  /// the main actor while the filesystem is queried.
  func mountedVolumes() async -> [Volume]
}

/// The before-and-after state reported for a filesystem mount notification.
struct VolumeChange: Equatable, Sendable {
  let previous: [Volume]
  let current: [Volume]

  /// Roots whose mount identity or relevant presentation/access properties changed.
  var affectedRoots: [URL] {
    let previousByRoot = Dictionary(uniqueKeysWithValues: previous.map { ($0.url.normalizedVolumeRoot, $0) })
    let currentByRoot = Dictionary(uniqueKeysWithValues: current.map { ($0.url.normalizedVolumeRoot, $0) })
    let roots = Set(previousByRoot.keys).union(currentByRoot.keys)
    return roots.filter { previousByRoot[$0] != currentByRoot[$0] }.sorted { $0.path < $1.path }
  }

  /// Network roots that require validation after any mount notification. Network
  /// shares can remain reachable at the same pathname while their backing
  /// connection or remote contents change without a distinguishable local diff.
  var networkRootsRequiringFreshnessValidation: [URL] {
    Set((previous + current).filter(\.isNetwork).map { $0.url.normalizedVolumeRoot })
      .sorted { $0.path < $1.path }
  }
}

enum VolumeChangePaneRefreshAction: Equatable {
  case fallBack
  case revalidate
  case none
}

/// Routes a mount change to panes without coupling the decision to AppKit.
enum VolumeChangePaneRefreshRouter {
  static func actions(
    for directories: [URL],
    change: VolumeChange,
    isReachable: (URL) -> Bool
  ) -> [VolumeChangePaneRefreshAction] {
    directories.map { directory in
      guard isReachable(directory) else { return .fallBack }
      guard change.affectedRoots.contains(where: { directory.isDescendant(of: $0) })
        || change.networkRootsRequiringFreshnessValidation.contains(where: { directory.isDescendant(of: $0) })
      else {
        return .none
      }
      return .revalidate
    }
  }
}

/// Publishes a fresh mounted-volume snapshot after Finder reports a mount change.
/// NSWorkspace delivers these notifications on its own notification center; hopping
/// through the main actor keeps consumers safe to update AppKit directly.
@MainActor
final class VolumeChangeMonitor {
  var onVolumesChanged: ((VolumeChange) -> Void)?

  private let discovery: any VolumeDiscovering
  private let notificationCenter: NotificationCenter
  private var observers: [NSObjectProtocol] = []
  private var lastKnownVolumes: [Volume]
  private var discoveryTask: Task<Void, Never>?
  private var discoveryGeneration = 0

  init(
    discovery: any VolumeDiscovering = VolumeDiscoveryService(),
    notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.discovery = discovery
    self.notificationCenter = notificationCenter
    self.lastKnownVolumes = []
    let names: [Notification.Name] = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification]
    observers = names.map { name in
      notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.publishRefresh() }
      }
    }
    refreshKnownVolumes(publishChange: false)
  }

  func publishRefresh() {
    // A notification may arrive while querying a slow network volume. Publish
    // the last safe snapshot immediately so AppKit clients can react without
    // waiting for discovery; a second notification follows with fresh data.
    onVolumesChanged?(VolumeChange(previous: lastKnownVolumes, current: lastKnownVolumes))
    refreshKnownVolumes(publishChange: true)
  }

  private func refreshKnownVolumes(publishChange: Bool) {
    discoveryGeneration += 1
    let generation = discoveryGeneration
    discoveryTask?.cancel()
    let discovery = discovery
    discoveryTask = Task { [weak self] in
      let volumes = await discovery.mountedVolumes()
      guard !Task.isCancelled else { return }
      guard let self, self.discoveryGeneration == generation else { return }
      let change = VolumeChange(previous: self.lastKnownVolumes, current: volumes)
      self.lastKnownVolumes = volumes
      if publishChange { self.onVolumesChanged?(change) }
    }
  }

  deinit {
    discoveryTask?.cancel()
    observers.forEach(notificationCenter.removeObserver)
  }
}

private extension URL {
  var normalizedVolumeRoot: URL {
    standardizedFileURL.resolvingSymlinksInPath()
  }

  func isDescendant(of root: URL) -> Bool {
    let directoryComponents = standardizedFileURL.resolvingSymlinksInPath().pathComponents
    let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    return directoryComponents.starts(with: rootComponents)
  }
}

/// Discovers mounted volumes through FileManager's mounted-volume API.
final class VolumeDiscoveryService: VolumeDiscovering {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func mountedVolumes() async -> [Volume] {
    await Task.detached(priority: .utility) { [fileManager] in
      Self.discoverMountedVolumes(using: fileManager)
    }.value
  }

  private static func discoverMountedVolumes(using fileManager: FileManager) -> [Volume] {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey,
      .volumeIsRemovableKey,
      .volumeIsLocalKey,
      .volumeIsReadOnlyKey,
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
    ]
    let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
    let urls =
      fileManager.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: options
      ) ?? []

    return sortedVolumes(
      urls.compactMap { url in
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isLocal = values.volumeIsLocal ?? false
        return Volume(
          url: url,
          displayName: values.volumeName ?? url.lastPathComponent,
          isRemovable: values.volumeIsRemovable ?? false,
          isLocal: isLocal,
          isNetwork: !isLocal,
          isReadOnly: values.volumeIsReadOnly ?? false,
          totalCapacity: values.volumeTotalCapacity.map(Int64.init),
          availableCapacity: values.volumeAvailableCapacity.map(Int64.init)
        )
      })
  }

  static func sortedVolumes(_ volumes: [Volume]) -> [Volume] {
    volumes.sorted { lhs, rhs in
      lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }
}

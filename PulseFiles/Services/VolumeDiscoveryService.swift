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
  func mountedVolumes() -> [Volume]
}

/// Publishes a fresh mounted-volume snapshot after Finder reports a mount change.
/// NSWorkspace delivers these notifications on its own notification center; hopping
/// through the main actor keeps consumers safe to update AppKit directly.
@MainActor
final class VolumeChangeMonitor {
  var onVolumesChanged: (([Volume]) -> Void)?

  private let discovery: any VolumeDiscovering
  private let notificationCenter: NotificationCenter
  private var observers: [NSObjectProtocol] = []

  init(
    discovery: any VolumeDiscovering = VolumeDiscoveryService(),
    notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.discovery = discovery
    self.notificationCenter = notificationCenter
    let names: [Notification.Name] = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification]
    observers = names.map { name in
      notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.publishRefresh() }
      }
    }
  }

  func publishRefresh() {
    onVolumesChanged?(discovery.mountedVolumes())
  }

  deinit {
    observers.forEach(notificationCenter.removeObserver)
  }
}

/// Discovers mounted volumes through FileManager's mounted-volume API.
final class VolumeDiscoveryService: VolumeDiscovering {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func mountedVolumes() -> [Volume] {
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

    return Self.sortedVolumes(
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

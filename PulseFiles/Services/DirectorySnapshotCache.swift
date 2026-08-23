import PulseFilesUtilities
import PulseFilesModels
import Foundation

package struct DirectorySnapshotMetadata: Equatable, Sendable {
    package let resourceIdentifier: String?
    package let changeDate: Date?
}

@MainActor
package final class DirectorySnapshotCache {
    package struct Limits: Equatable, Sendable {
        package let maximumEntryCount: Int
        package let maximumItemCount: Int

        package init(maximumEntryCount: Int = 32, maximumItemCount: Int = 20_000) {
            precondition(maximumEntryCount >= 0)
            precondition(maximumItemCount >= 0)
            self.maximumEntryCount = maximumEntryCount
            self.maximumItemCount = maximumItemCount
        }
    }

    package struct Key: Hashable {
        let directory: URL
        let includesHiddenFiles: Bool
        let sort: FileSortDescriptor

        init(directory: URL, includesHiddenFiles: Bool, sort: FileSortDescriptor) {
            self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
            self.includesHiddenFiles = includesHiddenFiles
            self.sort = sort
        }
    }

    package struct Snapshot {
        let metadata: DirectorySnapshotMetadata
        let items: [FileItem]
    }

    private struct Entry {
        let snapshot: Snapshot
        var lastAccess: UInt64
    }

    private let limits: Limits
    private var snapshots: [Key: Entry] = [:]
    private var dirtyDirectories = Set<URL>()
    private var accessCounter: UInt64 = 0
    private var totalItemCount = 0

    package init(limits: Limits = Limits()) {
        self.limits = limits
    }

    package func snapshot(for key: Key) -> Snapshot? {
        guard !dirtyDirectories.contains(key.directory) else { return nil }
        guard var entry = snapshots[key] else { return nil }
        entry.lastAccess = nextAccess()
        snapshots[key] = entry
        return entry.snapshot
    }

    package func store(_ items: [FileItem], metadata: DirectorySnapshotMetadata, for key: Key) {
        if let replaced = snapshots[key] {
            totalItemCount -= replaced.snapshot.items.count
        }
        snapshots[key] = Entry(
            snapshot: Snapshot(metadata: metadata, items: items),
            lastAccess: nextAccess()
        )
        totalItemCount += items.count
        dirtyDirectories.remove(key.directory)
        evictIfNeeded()
    }

    package func invalidate(directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        dirtyDirectories.insert(normalizedDirectory)
        let keys = snapshots.keys.filter { $0.directory == normalizedDirectory }
        for key in keys {
            removeValue(for: key)
        }
    }

    /// Releases every retained snapshot. Pane teardown and memory-pressure handlers
    /// call this explicitly so cached directory listings do not prolong memory use.
    package func clear() {
        snapshots.removeAll(keepingCapacity: false)
        dirtyDirectories.removeAll(keepingCapacity: false)
        totalItemCount = 0
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    private func evictIfNeeded() {
        while snapshots.count > limits.maximumEntryCount || totalItemCount > limits.maximumItemCount {
            guard let leastRecentlyUsed = snapshots.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else {
                return
            }
            removeValue(for: leastRecentlyUsed)
        }
    }

    private func removeValue(for key: Key) {
        guard let removed = snapshots.removeValue(forKey: key) else { return }
        totalItemCount -= removed.snapshot.items.count
    }
}

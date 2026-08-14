import PulseFilesUtilities
import PulseFilesModels
import Foundation

package struct DirectorySnapshotMetadata: Equatable, Sendable {
    package let resourceIdentifier: String?
    package let changeDate: Date?
}

@MainActor
package final class DirectorySnapshotCache {
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

    private var snapshots: [Key: Snapshot] = [:]
    private var dirtyDirectories = Set<URL>()

    package func snapshot(for key: Key) -> Snapshot? {
        guard !dirtyDirectories.contains(key.directory) else { return nil }
        return snapshots[key]
    }

    package func store(_ items: [FileItem], metadata: DirectorySnapshotMetadata, for key: Key) {
        snapshots[key] = Snapshot(metadata: metadata, items: items)
        dirtyDirectories.remove(key.directory)
    }

    package func invalidate(directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        dirtyDirectories.insert(normalizedDirectory)
        snapshots = snapshots.filter { $0.key.directory != normalizedDirectory }
    }
}

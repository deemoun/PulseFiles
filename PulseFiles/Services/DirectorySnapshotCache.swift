import Foundation

struct DirectorySnapshotMetadata: Equatable, Sendable {
    let resourceIdentifier: String?
    let changeDate: Date?
}

@MainActor
final class DirectorySnapshotCache {
    struct Key: Hashable {
        let directory: URL
        let includesHiddenFiles: Bool
        let sort: FileSortDescriptor

        init(directory: URL, includesHiddenFiles: Bool, sort: FileSortDescriptor) {
            self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
            self.includesHiddenFiles = includesHiddenFiles
            self.sort = sort
        }
    }

    struct Snapshot {
        let metadata: DirectorySnapshotMetadata
        let items: [FileItem]
    }

    private var snapshots: [Key: Snapshot] = [:]
    private var dirtyDirectories = Set<URL>()

    func snapshot(for key: Key) -> Snapshot? {
        guard !dirtyDirectories.contains(key.directory) else { return nil }
        return snapshots[key]
    }

    func store(_ items: [FileItem], metadata: DirectorySnapshotMetadata, for key: Key) {
        snapshots[key] = Snapshot(metadata: metadata, items: items)
        dirtyDirectories.remove(key.directory)
    }

    func invalidate(directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        dirtyDirectories.insert(normalizedDirectory)
        snapshots = snapshots.filter { $0.key.directory != normalizedDirectory }
    }
}

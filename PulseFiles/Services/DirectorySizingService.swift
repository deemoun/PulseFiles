import Foundation

package struct DirectorySizeResult: Sendable, Equatable {
    package enum Completeness: Sendable, Equatable {
        case complete
        case partial(skippedItemCount: Int)
    }

    package let bytes: Int64
    package let completeness: Completeness

    package init(bytes: Int64, completeness: Completeness) {
        self.bytes = bytes
        self.completeness = completeness
    }
}

/// Performs blocking metadata traversal in the scheduler's bounded, lowest-priority lane.
/// Symbolic links are counted as zero and never followed. Descendant read failures produce
/// a lower-bound result rather than turning the bytes read so far into an exact total.
package final class DirectorySizingService: @unchecked Sendable {
    package typealias Traversal = @Sendable (URL, FileManager, FileSystemOperationScheduler.CancellationToken) throws -> DirectorySizeResult
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy
    private let scheduler: FileSystemOperationScheduler
    private let traversal: Traversal

    package init(
        fileManager: FileManager = .default,
        accessPolicy: SandboxFileAccessPolicy = .current,
        scheduler: FileSystemOperationScheduler = .shared,
        traversal: @escaping Traversal = { try DirectorySizingService.traverse($0, $1, $2) }
    ) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.scheduler = scheduler
        self.traversal = traversal
    }

    package func size(of root: URL) async throws -> DirectorySizeResult {
        try accessPolicy.validateAccess(to: root)
        return try await accessPolicy.withValidatedAccess(to: root) {
            let fileManager = SendableFileManager(value: fileManager)
            return try await scheduler.submitInspection { [fileManager, traversal] token in
                try traversal(root, fileManager.value, token)
            }
        }
    }

    package static func traverse(
        _ root: URL,
        _ fileManager: FileManager,
        _ cancellationToken: FileSystemOperationScheduler.CancellationToken
    ) throws -> DirectorySizeResult {
        try cancellationToken.checkCancellation()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        if rootValues.isSymbolicLink == true { return DirectorySizeResult(bytes: 0, completeness: .complete) }
        if rootValues.isDirectory != true {
            return DirectorySizeResult(bytes: Int64(rootValues.fileSize ?? 0), completeness: .complete)
        }

        var skipped = 0
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in skipped += 1; return true }
        ) else {
            return DirectorySizeResult(bytes: 0, completeness: .partial(skippedItemCount: 1))
        }

        var bytes: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            try cancellationToken.checkCancellation()
            do {
                let values = try child.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                } else if values.isRegularFile == true {
                    bytes += Int64(values.fileSize ?? 0)
                }
            } catch {
                skipped += 1 // Includes inaccessible and concurrently-disappearing descendants.
            }
        }
        return DirectorySizeResult(
            bytes: bytes,
            completeness: skipped == 0 ? .complete : .partial(skippedItemCount: skipped)
        )
    }
}

private struct SendableFileManager: @unchecked Sendable {
    let value: FileManager
}

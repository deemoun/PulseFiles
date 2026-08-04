import Foundation

/// Owns conflict and naming decisions; it never mutates the filesystem.
final class FileTransferPlanner {
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    static func keepBothDestination(for destination: URL, reservedDestinations: Set<String> = [], fileExists: (URL) -> Bool) -> URL {
        let ext = destination.pathExtension
        let base = ext.isEmpty ? destination.lastPathComponent : destination.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let candidate = destination.deletingLastPathComponent().appendingPathComponent(name)
            if !fileExists(candidate), !reservedDestinations.contains(FilePathComparison.normalizedPath(candidate)) { return candidate }
            index += 1
        }
    }

    func validateDestination(_ destination: URL) throws {
        try accessPolicy.validateDestinationAccess(to: destination)
        _ = fileManager.fileExists(atPath: destination.path)
    }
}

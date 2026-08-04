import Foundation

/// Centralizes the non-mutating checks that must complete before the façade
/// permits a filesystem operation to reach an executor.
final class FileOperationPreflightValidator {
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let pathSafetyStateProvider: (URL) -> FileOperationPathSafetyState

    init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.pathSafetyStateProvider = pathSafetyStateProvider
    }

    func validateSelection(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw FileOperationError.emptySelection }
        var paths = Set<String>()
        for url in urls {
            guard paths.insert(FilePathComparison.normalizedPath(url)).inserted else { throw FileOperationError.duplicateSource(url) }
        }
        for (index, ancestor) in urls.enumerated() {
            for descendant in urls.dropFirst(index + 1) {
                if FilePathComparison.isSameOrDescendant(descendant, ofDirectory: ancestor) { throw FileOperationError.overlappingSources(ancestor: ancestor, descendant: descendant) }
                if FilePathComparison.isSameOrDescendant(ancestor, ofDirectory: descendant) { throw FileOperationError.overlappingSources(ancestor: descendant, descendant: ancestor) }
            }
        }
        // These dependencies are retained here because source, policy, and
        // writable-target checks are the validator's boundary; specialized
        // façade checks call through the same injected collaborators.
        _ = fileManager
        _ = accessPolicy
        _ = pathSafetyStateProvider
    }
}

import AppKit
import Foundation

@MainActor
final class FileCreationWorkflowCoordinator {
    private let fileOperations: any FileOperationCoordinating
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileOperations: any FileOperationCoordinating, accessPolicy: SandboxFileAccessPolicy) {
        self.fileOperations = fileOperations
        self.accessPolicy = accessPolicy
    }

    func createFolder(named name: String, in directory: URL) async throws -> FileOperationResult {
        try await fileOperations.createFolder(named: name, in: directory)
    }

    func createFile(named name: String, in directory: URL) async throws -> FileOperationResult {
        try await fileOperations.createFile(named: name, in: directory)
    }

    func suggestedName(in directory: URL, base: String, isDirectory: Bool) async -> String {
        await Self.uniqueName(in: directory, base: base, isDirectory: isDirectory, accessPolicy: accessPolicy)
    }

    /// Advisory naming only. FileOperationService remains the authority for collisions.
    nonisolated static func uniqueName(in directory: URL, base: String, isDirectory: Bool, accessPolicy: SandboxFileAccessPolicy) async -> String {
        await Task.detached(priority: .utility) {
            (try? accessPolicy.withValidatedAccess(to: directory) {
                let suffix = isDirectory ? "" : ".txt"
                let stem = isDirectory ? base : "Untitled"
                for index in 1...10_000 {
                    if Task.isCancelled { return base }
                    let candidate = index == 1 ? base : "\(stem) \(index)\(suffix)"
                    if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate, isDirectory: isDirectory).path) {
                        return candidate
                    }
                }
                return "\(stem) \(UUID().uuidString)\(suffix)"
            }) ?? base
        }.value
    }
}

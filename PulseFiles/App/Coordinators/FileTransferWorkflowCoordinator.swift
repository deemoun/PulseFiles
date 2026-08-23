import AppKit
import Foundation

@MainActor
final class FileTransferWorkflowCoordinator {
    let fileOperations: any FileOperationCoordinating
    let clipboard: any FileClipboardProviding
    private let accessPolicy: SandboxFileAccessPolicy
    private var dropGeneration = 0

    init(fileOperations: any FileOperationCoordinating, clipboard: any FileClipboardProviding, accessPolicy: SandboxFileAccessPolicy) {
        self.fileOperations = fileOperations
        self.clipboard = clipboard
        self.accessPolicy = accessPolicy
    }

    func writeToClipboard(_ urls: [URL], operation: FileClipboard.Operation) throws {
        for url in urls { try accessPolicy.validateAccess(to: url) }
        clipboard.write(urls: urls, operation: operation)
    }

    func clipboardPayload() -> FileClipboard.Payload? { clipboard.read() }

    func pasteOperation(payload: FileClipboard.Payload, destination: URL) throws -> (String, FileOperationRequest, (@escaping FileConflictHandler, FileOperationProgressHandler?) async throws -> FileOperationResult) {
        let request = try self.request(sources: payload.urls, destination: destination)
        let name = payload.operation == .copy ? "Paste Copy".localized : "Paste Move".localized
        return (name, request, { [fileOperations] conflicts, progress in
            switch payload.operation {
            case .copy: return try await fileOperations.copy(request, conflictHandler: conflicts, progressHandler: progress)
            case .move: return try await fileOperations.move(request, conflictHandler: conflicts, progressHandler: progress)
            }
        })
    }

    func validateDrop(sources: [URL], destination: URL, probe: any FileSystemProbing) async throws -> Int {
        dropGeneration += 1; let generation = dropGeneration
        let destinationAnswer = try await accessPolicy.withValidatedAccess(to: destination) {
            await probe.isDirectory(destination, deadline: .milliseconds(250))
        }
        guard case .value(let isDirectory) = destinationAnswer, isDirectory else { throw FileOperationError.destinationNotDirectory(destination) }
        for source in sources {
            let answer = try await accessPolicy.withValidatedAccess(to: source) { await probe.exists(source, deadline: .milliseconds(250)) }
            guard case .value(true) = answer else { throw FileOperationError.sourceMissing(source) }
        }
        return generation
    }

    func isCurrentDrop(generation: Int) -> Bool { generation == dropGeneration }

    func request(sources: [URL], destination: URL) throws -> FileOperationRequest {
        try Self.validatedRequest(sources: sources, destination: destination)
    }

    static func validatedRequest(sources: [URL], destination: URL) throws -> FileOperationRequest {
        guard FilePathComparison.firstDirectoryContaining(destination, among: sources) == nil else {
            throw TransferError.destinationInsideSource
        }
        return FileOperationRequest(sources: sources, destinationDirectory: destination)
    }

    enum TransferError: LocalizedError {
        case destinationInsideSource
        var errorDescription: String? { "Cannot copy or move an item into itself or one of its subfolders.".localized }
    }
}

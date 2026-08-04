import AppKit
import Foundation

@MainActor
final class FileTransferWorkflowCoordinator {
    let fileOperations: any FileOperationCoordinating
    let clipboard: any FileClipboardProviding
    private let accessPolicy: SandboxFileAccessPolicy

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

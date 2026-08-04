import Foundation

/// Holds the mutation dependencies used by staged and recursive transfers.
/// The façade remains responsible for invoking it only after preflight.
final class FileTransferExecutor {
    let fileManager: FileOperationFileManaging
    let streamingCopier: FileOperationStreamingCopying
    let descriptorOperator: DescriptorRelativeFileOperator

    init(fileManager: FileOperationFileManaging, streamingCopier: FileOperationStreamingCopying, descriptorOperator: DescriptorRelativeFileOperator) {
        self.fileManager = fileManager
        self.streamingCopier = streamingCopier
        self.descriptorOperator = descriptorOperator
    }

    func checkCancellation() throws { try Task.checkCancellation() }
}

import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

package final class FileHandleStreamingCopier: FileOperationStreamingCopying {
    private let chunkSize = 1_048_576

    package func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        #if os(macOS)
        let parent = try OpenDirectoryCapability(directory: destination.deletingLastPathComponent())
        defer { parent.close() }
        try await copyFile(from: source, toParent: parent, named: destination.lastPathComponent, progress: progress)
        #else
        // FileHandle reads and writes can block, particularly for network
        // volumes. Use a detached executor even when this copier is used
        // independently of FileOperationService.
        let worker = Task.detached(priority: .utility) { [chunkSize = self.chunkSize] in
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let writer = try FileHandle(forWritingTo: destination)
            defer { try? writer.close() }

            while true {
                try Task.checkCancellation()
                guard let data = try reader.read(upToCount: chunkSize), !data.isEmpty else { break }
                try writer.write(contentsOf: data)
                try await progress(data.count)
            }
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        #endif
    }

    #if os(macOS)
    package func copyFile(from source: URL, toParent parent: OpenDirectoryCapability, named name: String, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        try parent.revalidate()
        try OpenDirectoryCapability.validateName(name)
        let destinationFD = try parent.openNewRegularFile(named: name)
        let worker = Task.detached(priority: .utility) { [chunkSize = self.chunkSize] in
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            let writer = FileHandle(fileDescriptor: destinationFD, closeOnDealloc: true)
            defer { try? writer.close() }
            while true {
                try Task.checkCancellation()
                guard let data = try reader.read(upToCount: chunkSize), !data.isEmpty else { break }
                try writer.write(contentsOf: data)
                try await progress(data.count)
            }
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    #endif
}

package extension FileManager: FileOperationFileManaging {
    package func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }

    package func createEmptyFile(at url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
    }
}

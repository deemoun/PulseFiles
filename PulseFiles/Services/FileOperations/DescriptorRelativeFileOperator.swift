import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

/// Performs mutations relative to a verified parent directory descriptor on
/// macOS, preventing path replacement between validation and mutation.
package final class DescriptorRelativeFileOperator {
    private let fileManager: FileOperationFileManaging

    package init(fileManager: FileOperationFileManaging) {
        self.fileManager = fileManager
    }

    package func verifyExistingItem(_ url: URL) throws {
        #if os(macOS)
        guard fileManager is FileManager else {
            guard fileManager.fileExists(atPath: url.path) else { throw FileOperationError.sourceMissing(url) }
            return
        }
        let parent = try OpenDirectoryCapability(directory: url.deletingLastPathComponent())
        defer { parent.close() }
        let identity = try parent.itemIdentity(named: url.lastPathComponent)
        try parent.requireItem(named: url.lastPathComponent, identity: identity)
        #else
        guard fileManager.fileExists(atPath: url.path) else { throw FileOperationError.sourceMissing(url) }
        #endif
    }

    package func rename(_ source: URL, to destination: URL) throws {
        #if os(macOS)
        guard fileManager is FileManager else { try fileManager.moveItem(at: source, to: destination); return }
        let sourceParent = try OpenDirectoryCapability(directory: source.deletingLastPathComponent())
        defer { sourceParent.close() }
        let destinationParent = try OpenDirectoryCapability(directory: destination.deletingLastPathComponent())
        defer { destinationParent.close() }
        let identity = try sourceParent.itemIdentity(named: source.lastPathComponent)
        try sourceParent.requireItem(named: source.lastPathComponent, identity: identity)
        try sourceParent.renameItem(named: source.lastPathComponent, to: destinationParent, named: destination.lastPathComponent)
        #else
        try fileManager.moveItem(at: source, to: destination)
        #endif
    }

    package func remove(_ url: URL) throws {
        #if os(macOS)
        guard fileManager is FileManager else { try fileManager.removeItem(at: url); return }
        let parent = try OpenDirectoryCapability(directory: url.deletingLastPathComponent())
        defer { parent.close() }
        try parent.removeItem(named: url.lastPathComponent)
        #else
        try fileManager.removeItem(at: url)
        #endif
    }

    package func create(_ url: URL, isDirectory: Bool) throws {
        #if os(macOS)
        guard fileManager is FileManager else {
            if isDirectory { try fileManager.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try fileManager.createEmptyFile(at: url) }
            return
        }
        let parent = try OpenDirectoryCapability(directory: url.deletingLastPathComponent())
        defer { parent.close() }
        if isDirectory { try parent.createDirectory(named: url.lastPathComponent) }
        else { Darwin.close(try parent.openNewRegularFile(named: url.lastPathComponent)) }
        #else
        if isDirectory { try fileManager.createDirectory(at: url, withIntermediateDirectories: false) }
        else { try fileManager.createEmptyFile(at: url) }
        #endif
    }

    package func createSymbolicLink(at url: URL, destination: String) throws {
        #if os(macOS)
        guard fileManager is FileManager else { try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: destination); return }
        let parent = try OpenDirectoryCapability(directory: url.deletingLastPathComponent())
        defer { parent.close() }
        try parent.createSymbolicLink(named: url.lastPathComponent, destination: destination)
        #else
        try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        #endif
    }
}

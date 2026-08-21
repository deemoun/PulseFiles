import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// Centralizes the non-mutating checks that must complete before the façade
/// permits a filesystem operation to reach an executor.
package final class FileOperationPreflightValidator {
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let pathSafetyStateProvider: (URL) -> FileOperationPathSafetyState

    package init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy, pathSafetyStateProvider: @escaping (URL) -> FileOperationPathSafetyState) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.pathSafetyStateProvider = pathSafetyStateProvider
    }

    package func validateSelection(_ urls: [URL]) throws {
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

    package enum SourceItemKind { case file, directory, symbolicLink(destination: String), finderAlias }

    package func sourceItemKind(at url: URL) throws -> SourceItemKind {
        if pathSafetyStateProvider(url).isFinderAlias { return .finderAlias }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true { return .symbolicLink(destination: try fileManager.destinationOfSymbolicLink(atPath: url.path)) }
        return values.isDirectory == true ? .directory : .file
    }

    package func preflightCreation(rawName: String, in directory: URL, isDirectory: Bool) throws -> URL {
        try validateExistingDirectory(directory)
        try validateWritableMutationTarget(directory)
        try accessPolicy.validateAccess(to: directory)
        let name = try FileNameValidator.validate(rawName, in: directory)
        let destination = directory.appendingPathComponent(name, isDirectory: isDirectory)
        try accessPolicy.validateDestinationAccess(to: destination)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.destinationExists(destination)
        }
        return destination
    }

    package func preflightTransferRequest(_ request: FileOperationRequest, isMove: Bool = false) throws {
        try validateExistingDirectory(request.destinationDirectory)
        try validateWritableMutationTarget(request.destinationDirectory)
        try accessPolicy.validateAccess(to: request.destinationDirectory)

        try preflightMultiSourceSelection(request.sources)
        if isMove {
            for source in request.sources {
                try validateWritableMutationTarget(source.deletingLastPathComponent())
            }
        }

        var normalizedDestinations = Set<String>()
        for source in request.sources {
            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try accessPolicy.validateDestinationAccess(to: destination)
            try validateDestination(destination, for: source)
            let normalizedDestination = FilePathComparison.normalizedPath(destination)
            guard normalizedDestinations.insert(normalizedDestination).inserted else {
                throw FileOperationError.duplicateDestination(destination)
            }
        }
    }

    package func preflightRename(source: URL, destination: URL) throws {
        try validateExistingSource(source)
        try validateAvailableSource(source)
        try validateSourceAccess(source)
        try accessPolicy.validateDestinationAccess(to: destination)
        try validateExistingDirectory(source.deletingLastPathComponent())
        try validateWritableMutationTarget(source.deletingLastPathComponent())
        try validateDestination(destination, for: source)
        if fileManager.fileExists(atPath: destination.path), FilePathComparison.normalizedPath(source) != FilePathComparison.normalizedPath(destination) {
            throw FileOperationError.destinationExists(destination)
        }
    }

    package func preflightDelete(_ urls: [URL]) throws {
        try preflightMultiSourceSelection(urls)
        for url in urls {
            try validateWritableMutationTarget(url.deletingLastPathComponent())
        }
    }

    package func preflightMultiSourceSelection(_ urls: [URL]) throws {
        try validateSelection(urls)

        var normalizedSources = Set<String>()
        for url in urls {
            try validateExistingSource(url)
            try validateAvailableSource(url)
            try validateMutationSupported(url)
            try validateSourceAccess(url)
            guard normalizedSources.insert(FilePathComparison.normalizedPath(url)).inserted else {
                throw FileOperationError.duplicateSource(url)
            }
        }

        for (ancestorIndex, ancestor) in urls.enumerated() {
            for descendant in urls.dropFirst(ancestorIndex + 1) {
                if FilePathComparison.isSameOrDescendant(descendant, ofDirectory: ancestor) {
                    throw FileOperationError.overlappingSources(ancestor: ancestor, descendant: descendant)
                }
                if FilePathComparison.isSameOrDescendant(ancestor, ofDirectory: descendant) {
                    throw FileOperationError.overlappingSources(ancestor: descendant, descendant: ancestor)
                }
            }
        }
    }

    package func validateExistingSource(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceMissing(url)
        }
    }

    package func validateAvailableSource(_ url: URL, allowingPlaceholder: Bool = false) throws {
        let state = pathSafetyStateProvider(url)
        guard state.isAvailable else { throw FileOperationError.volumeUnavailable(url) }
        guard allowingPlaceholder || !state.isICloudPlaceholder else { throw FileOperationError.iCloudItemNotDownloaded(url) }
    }

    package func validateMutationSupported(_ url: URL) throws {
        if case .finderAlias = try sourceItemKind(at: url) {
            throw FileOperationError.finderAliasMutationUnsupported(url)
        }
    }

    package func validateWritableMutationTarget(_ url: URL) throws {
        let state = pathSafetyStateProvider(url)
        guard state.isAvailable else { throw FileOperationError.volumeUnavailable(url) }
        guard !state.isReadOnlyVolume else { throw FileOperationError.readOnlyVolume(url) }
    }

    package func validateSourceAccess(_ source: URL) throws {
        if case .symbolicLink = try sourceItemKind(at: source) {
            // Access to the link is governed by its containing directory. Do
            // not resolve its target: the copy policy above never traverses it.
            try accessPolicy.validateAccess(to: source.deletingLastPathComponent())
        } else {
            try accessPolicy.validateAccess(to: source)
        }
    }

    package func validateExistingDirectory(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.destinationDirectoryMissing(url)
        }
        guard case .directory? = try? sourceItemKind(at: url) else {
            throw FileOperationError.destinationNotDirectory(url)
        }
    }

    package func validateDestination(_ destination: URL, for source: URL) throws {
        if FilePathComparison.isSameOrDescendant(destination, ofDirectory: source) {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
    }


    package static func defaultDestinationCapacity(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
    }

    package static func defaultVolumeIdentifier(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey]), let identifier = values.volumeIdentifier else { return nil }
        if let identifier = identifier as? UUID {
            return identifier.uuidString
        }
        return String(describing: identifier)
    }

    package static func defaultPathSafetyState(for url: URL) -> FileOperationPathSafetyState {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey, .isAliasFileKey]) else {
            return FileOperationPathSafetyState(isAvailable: false)
        }
        return FileOperationPathSafetyState(
            isAvailable: true,
            isReadOnlyVolume: values.volumeIsReadOnly == true,
            isICloudPlaceholder: values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current,
            isFinderAlias: values.isAliasFile == true
        )
    }

    package func itemIdentity(at url: URL) -> String? {
        guard let identifier = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return nil }
        return String(describing: identifier)
    }
}

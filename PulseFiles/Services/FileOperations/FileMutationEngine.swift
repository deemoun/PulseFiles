// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesModels
import PulseFilesUtilities
import Foundation

/// The deliberately small mutation surface shared by transfers, archives, and
/// batch rename.  Callers may inspect files through their read-side services,
/// but all namespace changes pass through this engine.
package final class FileMutationEngine {
    package struct StagingArea {
        package let operationID: UUID
        package let directory: URL
        package let marker: URL
    }

    package struct Publication {
        package let stagedURL: URL
        package let destinationURL: URL
        package let publishedIdentity: String
        package let backupURL: URL?
    }
    package struct RollbackReport {
        package let retainedDestinations: Set<URL>
        package let warnings: [FileOperationCleanupWarning]
    }

    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy
    private let validator: FileOperationPreflightValidator
    private let descriptorOperator: DescriptorRelativeFileOperator
    private let stagingRegistry: StagingOwnershipRegistry

    package init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy,
                 validator: FileOperationPreflightValidator, descriptorOperator: DescriptorRelativeFileOperator,
                 stagingRegistry: StagingOwnershipRegistry) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.validator = validator
        self.descriptorOperator = descriptorOperator
        self.stagingRegistry = stagingRegistry
    }

    package func validateReadableSource(_ url: URL, allowFinderAlias: Bool = false) throws {
        try validator.validateExistingSource(url)
        try validator.validateAvailableSource(url)
        if !allowFinderAlias { try validator.validateMutationSupported(url) }
        try validator.validateSourceAccess(url)
    }

    package func validateMutationDirectory(_ url: URL) throws {
        try validator.validateExistingDirectory(url)
        try validator.validateWritableMutationTarget(url)
        try accessPolicy.validateAccess(to: url)
    }

    package func validateDestination(_ url: URL) throws {
        try validator.validateWritableMutationTarget(url.deletingLastPathComponent())
        try accessPolicy.validateDestinationAccess(to: url)
    }

    package func rename(_ source: URL, to destination: URL) throws {
        try validateDestination(destination)
        try descriptorOperator.rename(source, to: destination)
    }

    package func createDirectory(_ url: URL) throws { try descriptorOperator.create(url, isDirectory: true) }
    package func createDirectoryTree(_ url: URL) throws {
        try validateDestination(url)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    package func createFile(_ url: URL) throws { try descriptorOperator.create(url, isDirectory: false) }
    package func remove(_ url: URL) throws { try descriptorOperator.remove(url) }

    package func makeStagingArea(in destinationDirectory: URL, prefix: String) throws -> StagingArea {
        try validateMutationDirectory(destinationDirectory)
        var directory: URL
        repeat { directory = destinationDirectory.appendingPathComponent(".pulsefiles-\(prefix)-\(UUID().uuidString)", isDirectory: true) }
        while fileManager.fileExists(atPath: directory.path)
        try accessPolicy.validateManagedStagingArea(directory, appropriateFor: destinationDirectory.appendingPathComponent("item"))
        try createDirectory(directory)
        let operationID = UUID()
        let marker = directory.appendingPathComponent(".pulsefiles-operation-\(operationID.uuidString)")
        do {
            try accessPolicy.validateManagedStagingArea(marker, appropriateFor: destinationDirectory.appendingPathComponent("item"))
            try createFile(marker)
            guard let stagingIdentity = StagingCleanupService.resourceIdentity(directory),
                  let destinationIdentity = StagingCleanupService.resourceIdentity(destinationDirectory) else {
                throw FileOperationError.temporarySiblingUnavailable(destination: destinationDirectory, prefix: prefix)
            }
            try stagingRegistry.register(.init(operationID: operationID, stagingURL: directory, createdAt: Date(),
                                               destinationURL: destinationDirectory, stagingIdentity: stagingIdentity,
                                               destinationIdentity: destinationIdentity, state: .active))
            return .init(operationID: operationID, directory: directory, marker: marker)
        } catch {
            try? descriptorOperator.remove(directory)
            throw error
        }
    }

    /// Publishes only after destination and staging parents have been checked.
    /// A replaced item remains in owned staging until the transaction commits.
    package func publish(_ stagedURL: URL, to destinationURL: URL, staging: StagingArea) throws -> Publication {
        try Task.checkCancellation()
        try validateDestination(destinationURL)
        guard fileManager.fileExists(atPath: staging.marker.path) else {
            throw FileOperationError.temporarySiblingUnavailable(destination: destinationURL, prefix: "managed")
        }
        var backup: URL?
        if fileManager.fileExists(atPath: destinationURL.path) {
            let candidate = staging.directory.appendingPathComponent("replacement-\(UUID().uuidString)")
            try descriptorOperator.rename(destinationURL, to: candidate)
            backup = candidate
        }
        do {
            try descriptorOperator.rename(stagedURL, to: destinationURL)
            guard let identity = validator.itemIdentity(at: destinationURL) else {
                throw FileOperationError.unsafeReplacement(destination: destinationURL, backup: backup ?? stagedURL)
            }
            return .init(stagedURL: stagedURL, destinationURL: destinationURL, publishedIdentity: identity, backupURL: backup)
        } catch {
            if let backup, !fileManager.fileExists(atPath: destinationURL.path) { try? descriptorOperator.rename(backup, to: destinationURL) }
            throw error
        }
    }

    package func rollback(_ publications: [Publication]) -> RollbackReport {
        var warnings: [FileOperationCleanupWarning] = []
        var retained = Set<URL>()
        for publication in publications.reversed() {
            do {
                let identityMatches = validator.itemIdentity(at: publication.destinationURL) == publication.publishedIdentity
                guard identityMatches else {
                    throw FileOperationError.unsafeReplacement(destination: publication.destinationURL,
                                                               backup: publication.backupURL ?? publication.stagedURL)
                }
                do { try descriptorOperator.rename(publication.destinationURL, to: publication.stagedURL) }
                catch { retained.insert(publication.destinationURL.standardizedFileURL); throw error }
                if let backup = publication.backupURL {
                    guard !fileManager.fileExists(atPath: publication.destinationURL.path) else { throw CocoaError(.fileWriteFileExists) }
                    try descriptorOperator.rename(backup, to: publication.destinationURL)
                }
            } catch {
                warnings.append(.init(url: publication.destinationURL,
                                      message: "Could not safely roll back the published item: \(error.localizedDescription)"))
            }
        }
        return .init(retainedDestinations: retained, warnings: warnings)
    }

    package func cleanup(_ staging: StagingArea) -> [FileOperationCleanupWarning] {
        guard fileManager.fileExists(atPath: staging.marker.path) else { return [] }
        do { try stagingRegistry.setState(.completed, operationID: staging.operationID) }
        catch { return [.init(url: staging.directory, message: error.localizedDescription)] }
        do {
            try descriptorOperator.remove(staging.directory)
            try stagingRegistry.remove(operationID: staging.operationID)
            return []
        } catch {
            return [.init(url: staging.directory,
                          message: "PulseFiles could not remove its managed staging area at %@. Review it and remove it manually after confirming it is no longer needed.".localized(with: staging.directory.path))]
        }
    }
}

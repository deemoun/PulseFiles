import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// Owns conflict and naming decisions; it never mutates the filesystem.
package final class FileTransferPlanner {
    private let fileManager: FileOperationFileManaging
    private let accessPolicy: SandboxFileAccessPolicy

    package init(fileManager: FileOperationFileManaging, accessPolicy: SandboxFileAccessPolicy) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    package static func keepBothDestination(for destination: URL, reservedDestinations: Set<String> = [], fileExists: (URL) -> Bool) -> URL {
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

    package func validateDestination(_ destination: URL) throws {
        try accessPolicy.validateDestinationAccess(to: destination)
        _ = fileManager.fileExists(atPath: destination.path)
    }

    package struct TransferPlan {
        let source: URL
        let destination: URL
        let conflictResolution: FileConflictResolution
        let replacesExistingDestination: Bool
    }

    package func resolveTransferPlans(
        for request: FileOperationRequest,
        conflictHandler: FileConflictHandler,
        conflictResolutionHandler: (URL, FileConflictResolution) -> Void
    ) async throws -> [TransferPlan] {
        var plans: [TransferPlan] = []
        var resolutionForRemainingConflicts: FileConflictResolution?
        var reservedDestinations = Set(request.sources.map {
            FilePathComparison.normalizedPath(request.destinationDirectory.appendingPathComponent($0.lastPathComponent))
        })

        for source in request.sources {
            let originalDestination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let replacesExistingDestination = fileManager.fileExists(atPath: originalDestination.path)
            let resolution: FileConflictResolution
            if replacesExistingDestination {
                let decision: FileConflictResolution
                if let resolutionForRemainingConflicts {
                    decision = resolutionForRemainingConflicts
                } else {
                    decision = await conflictHandler(originalDestination)
                }
                if let appliedResolution = decision.resolutionAppliedToRemainingConflicts {
                    resolutionForRemainingConflicts = appliedResolution
                    resolution = appliedResolution
                } else {
                    resolution = decision
                }
                conflictResolutionHandler(originalDestination, resolution)
            } else {
                resolution = .replace
            }

            if resolution == .cancel {
                plans.append(TransferPlan(source: source, destination: originalDestination, conflictResolution: .cancel, replacesExistingDestination: true))
                return plans
            }

            let destination: URL
            if resolution == .keepBoth {
                destination = Self.keepBothDestination(
                    for: originalDestination,
                    reservedDestinations: reservedDestinations,
                    fileExists: { self.fileManager.fileExists(atPath: $0.path) }
                )
            } else {
                destination = originalDestination
            }
            try accessPolicy.validateDestinationAccess(to: destination)
            reservedDestinations.insert(FilePathComparison.normalizedPath(destination))
            plans.append(TransferPlan(
                source: source,
                destination: destination,
                conflictResolution: resolution,
                replacesExistingDestination: resolution == .replace && replacesExistingDestination
            ))
        }

        return plans
    }
}

private extension FileConflictResolution {
    var resolutionAppliedToRemainingConflicts: FileConflictResolution? {
        switch self { case .applyToRemainingReplace: return .replace; case .applyToRemainingSkip: return .skip; case .applyToRemainingKeepBoth: return .keepBoth; default: return nil }
    }

}

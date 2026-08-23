import PulseFilesUtilities
import PulseFilesModels
import Foundation

package protocol SymbolicLinkDestinationReading {
    func destinationOfSymbolicLink(atPath path: String) throws -> String
    func fileExists(atPath path: String) -> Bool
}

extension FileManager: SymbolicLinkDestinationReading {}

package enum SymbolicLinkResolutionError: LocalizedError, Equatable {
    case targetDoesNotExist

    package var errorDescription: String? {
        switch self {
        case .targetDoesNotExist:
            return "The symbolic link target does not exist.".localized
        }
    }
}

/// Resolves exactly the destination stored in a link. It intentionally does
/// not recursively inspect subsequent links; normal pane navigation decides
/// how the returned one-hop target is opened.
package struct SymbolicLinkResolutionService {
    private let fileManager: SymbolicLinkDestinationReading

    package init(fileManager: SymbolicLinkDestinationReading = FileManager.default) {
        self.fileManager = fileManager
    }

    package func resolveOneHop(_ linkURL: URL) throws -> URL {
        let storedDestination = try fileManager.destinationOfSymbolicLink(atPath: linkURL.path)
        let target: URL
        if storedDestination.hasPrefix("/") {
            target = URL(fileURLWithPath: storedDestination)
        } else {
            target = linkURL.deletingLastPathComponent().appendingPathComponent(storedDestination)
        }
        let normalized = target.standardizedFileURL
        guard fileManager.fileExists(atPath: normalized.path) else {
            throw SymbolicLinkResolutionError.targetDoesNotExist
        }
        return normalized
    }
}

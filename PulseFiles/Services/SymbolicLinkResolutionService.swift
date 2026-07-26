import Foundation

protocol SymbolicLinkResolving {
    /// Reads and resolves one stored link destination. Link chains are deliberately not followed.
    func resolveOneHop(at linkURL: URL) throws -> URL
}

enum SymbolicLinkResolutionError: LocalizedError, Equatable {
    case notSymbolicLink
    case targetMissing(URL)

    var errorDescription: String? {
        switch self {
        case .notSymbolicLink: return "The focused item is not a symbolic link.".localized
        case .targetMissing: return "The symbolic link target no longer exists.".localized
        }
    }
}

struct SymbolicLinkResolutionService: SymbolicLinkResolving {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func resolveOneHop(at linkURL: URL) throws -> URL {
        // destinationOfSymbolicLink reads the stored payload once and does not resolve a chain.
        let stored: String
        do { stored = try fileManager.destinationOfSymbolicLink(atPath: linkURL.path) }
        catch { throw SymbolicLinkResolutionError.notSymbolicLink }
        let target = stored.hasPrefix("/")
            ? URL(fileURLWithPath: stored)
            : linkURL.deletingLastPathComponent().appendingPathComponent(stored)
        let normalized = target.standardizedFileURL
        guard fileManager.fileExists(atPath: normalized.path) else {
            throw SymbolicLinkResolutionError.targetMissing(normalized)
        }
        return normalized
    }
}

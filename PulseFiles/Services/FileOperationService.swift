import Foundation

enum FileOperationError: LocalizedError {
    case emptySelection
    case destinationInsideSource(source: URL, destination: URL)
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "No files are selected."
        case .destinationInsideSource:
            return "Invalid destination."
        case .destinationExists(let url):
            return "\(url.lastPathComponent) already exists."
        }
    }

    var failureReason: String? {
        switch self {
        case .emptySelection:
            return "Select one or more items in the active pane."
        case .destinationInsideSource(let source, let destination):
            return "Cannot copy or move \(source.lastPathComponent) into \(destination.path)."
        case .destinationExists(let url):
            return "The destination already contains \(url.lastPathComponent)."
        }
    }
}

enum FileConflictResolution {
    case replace
    case skip
    case cancel
}

struct FileOperationRequest {
    let sources: [URL]
    let destinationDirectory: URL
}

protocol FileOperationServicing {
    func copy(_ request: FileOperationRequest, conflictHandler: (URL) -> FileConflictResolution) throws
    func move(_ request: FileOperationRequest, conflictHandler: (URL) -> FileConflictResolution) throws
}

final class FileOperationService: FileOperationServicing {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    func copy(_ request: FileOperationRequest, conflictHandler: (URL) -> FileConflictResolution) throws {
        try validate(request)
        for source in request.sources {
            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try validateDestination(destination, for: source)
            switch try resolveConflict(at: destination, conflictHandler: conflictHandler) {
            case .replace:
                try removeExistingItem(at: destination)
            case .skip:
                continue
            case .cancel:
                return
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func move(_ request: FileOperationRequest, conflictHandler: (URL) -> FileConflictResolution) throws {
        try validate(request)
        for source in request.sources {
            let destination = request.destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try validateDestination(destination, for: source)
            switch try resolveConflict(at: destination, conflictHandler: conflictHandler) {
            case .replace:
                try removeExistingItem(at: destination)
            case .skip:
                continue
            case .cancel:
                return
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func validate(_ request: FileOperationRequest) throws {
        guard !request.sources.isEmpty else { throw FileOperationError.emptySelection }
        try accessPolicy.validateAccess(to: request.destinationDirectory)
        for source in request.sources {
            try accessPolicy.validateAccess(to: source)
        }
    }

    private func validateDestination(_ destination: URL, for source: URL) throws {
        try accessPolicy.validateAccess(to: destination)
        let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
    }

    private func resolveConflict(at destination: URL, conflictHandler: (URL) -> FileConflictResolution) throws -> FileConflictResolution {
        guard fileManager.fileExists(atPath: destination.path) else { return .replace }
        return conflictHandler(destination)
    }

    private func removeExistingItem(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

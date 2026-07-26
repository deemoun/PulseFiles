import AppKit
import Foundation
import UniformTypeIdentifiers

struct DirectoryItemReadFailure {
    let url: URL
    let error: Error
}

struct DirectoryContentsReadError: LocalizedError {
    let failures: [DirectoryItemReadFailure]

    var errorDescription: String? {
        "Could not read metadata for \(failures.count) item(s)."
    }
}

/// Indicates that a directory read did not finish before the pane's load deadline.
/// This is intentionally distinct from filesystem errors so callers can offer a
/// retry without presenting the folder as unreadable.
struct DirectoryLoadTimeoutError: LocalizedError, Equatable {
    let timeout: TimeInterval

    var errorDescription: String? {
        "Folder is taking too long to respond. Try again."
    }
}

/// The outcome of enumerating a directory. Metadata failures are reported rather
/// than silently removing the affected children from the listing.
struct DirectoryContentsResult {
    let items: [FileItem]
    let itemReadFailures: [DirectoryItemReadFailure]

    var isComplete: Bool { itemReadFailures.isEmpty }
}

protocol FileSystemServicing {
    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult
    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata
}

final class FileSystemService: FileSystemServicing {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy
    private let scheduler: FileSystemOperationScheduler

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current, scheduler: FileSystemOperationScheduler = .shared) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
        self.scheduler = scheduler
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        // FilePaneViewModel owns the validated operation scope so snapshot
        // metadata and enumeration do not start nested bookmark scopes.
        return try await self.scheduler.submit(priority: .visiblePane) {
                let keys: Set<URLResourceKey> = [
                .nameKey,
                .localizedNameKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isHiddenKey,
                .fileSizeKey,
                .totalFileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .addedToDirectoryDateKey,
                .contentAccessDateKey,
                .localizedTypeDescriptionKey,
                .contentTypeKey,
                .isPackageKey,
                .isAliasFileKey
            ]
            let urls = try self.fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: includingHidden ? [] : [.skipsHiddenFiles]
            )

            var items: [FileItem] = []
            var itemReadFailures: [DirectoryItemReadFailure] = []
            for child in urls {
                try Task.checkCancellation()
                do {
                    items.append(try self.fileItem(for: child))
                } catch {
                    itemReadFailures.append(DirectoryItemReadFailure(url: child, error: error))
                }
            }

                return DirectoryContentsResult(
                    items: Self.sorted(items, descriptor: sort),
                    itemReadFailures: itemReadFailures
                )
        }
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        return try await self.scheduler.submit(priority: .visiblePane) {
                let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey, .contentModificationDateKey])
                let identifier = values.fileResourceIdentifier.map { String(describing: $0) }
                return DirectorySnapshotMetadata(
                    resourceIdentifier: identifier,
                    changeDate: values.contentModificationDate
                )
        }
    }

    private func fileItem(for url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: [
            .nameKey,
            .localizedNameKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
            .localizedTypeDescriptionKey,
            .contentTypeKey,
            .isPackageKey,
            .isAliasFileKey
        ])
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let permissions = attributes?[.posixPermissions] as? Int
        let owner = attributes?[.ownerAccountName] as? String
        let group = attributes?[.groupOwnerAccountName] as? String
        let isDirectory = values.isDirectory == true
        let isLink = values.isSymbolicLink == true
        let isPackage = values.isPackage == true
        let type: FileItemType
        if isLink {
            type = .symbolicLink
        } else if isPackage {
            type = .package
        } else if isDirectory {
            type = .folder
        } else {
            type = .file
        }

        let filename = values.name ?? url.lastPathComponent
        let typeDescription = Self.typeDescription(
            for: url,
            values: values,
            fileType: type,
            isDirectory: isDirectory
        )
        let size = measuredSize(for: url, isDirectory: isDirectory, isSymbolicLink: isLink)
        return FileItem(
            url: url,
            filename: filename,
            displayName: values.localizedName ?? filename,
            fileExtension: url.pathExtension,
            fileType: type,
            isDirectory: isDirectory,
            isSymbolicLink: isLink,
            isHidden: values.isHidden == true || filename.hasPrefix("."),
            size: size,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            addedDate: values.addedToDirectoryDate,
            accessDate: values.contentAccessDate,
            posixPermissions: permissions,
            owner: owner,
            group: group,
            typeDescription: typeDescription,
            localizedTypeDescription: typeDescription,
            iconKey: FileIconKey(
                fileType: type,
                fileExtension: url.pathExtension,
                contentTypeIdentifier: values.contentType?.identifier,
                isAlias: values.isAliasFile == true
            )
        )
    }

    private static func typeDescription(
        for url: URL,
        values: URLResourceValues,
        fileType: FileItemType,
        isDirectory: Bool
    ) -> String {
        if let localizedTypeDescription = values.localizedTypeDescription, !localizedTypeDescription.isEmpty {
            return localizedTypeDescription
        }

        if fileType == .symbolicLink {
            return "Symbolic Link"
        }
        if values.isAliasFile == true {
            return "Finder Alias (not supported for mutation)"
        }
        if fileType == .package {
            return "Package"
        }
        if isDirectory {
            return "Folder"
        }

        if let localizedDescription = values.contentType?.localizedDescription
            ?? UTType(filenameExtension: url.pathExtension)?.localizedDescription,
            !localizedDescription.isEmpty {
            return localizedDescription
        }

        return "File"
    }

    private func measuredSize(for url: URL, isDirectory: Bool, isSymbolicLink: Bool) -> Int64 {
        if isDirectory && !isSymbolicLink {
            return 0
        }

        let resourceValues = try? url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey])
        if let totalFileSize = resourceValues?.totalFileSize {
            return Int64(totalFileSize)
        }
        if let fileSize = resourceValues?.fileSize {
            return Int64(fileSize)
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let attributeSize = attributes[.size] as? NSNumber {
            return attributeSize.int64Value
        }
        return 0
    }

    static func sorted(_ items: [FileItem], descriptor: FileSortDescriptor) -> [FileItem] {
        items.sorted { lhs, rhs in
            if descriptor.foldersFirst && lhs.isDirectory != rhs.isDirectory {
                // Keep folders grouped before files regardless of ascending/descending order.
                return lhs.isDirectory && !rhs.isDirectory
            }

            let stringCompare: (String, String) -> ComparisonResult = { left, right in
                switch descriptor.comparisonMode {
                case .naturalLocalized: return left.localizedStandardCompare(right)
                case .caseInsensitive: return left.compare(right, options: [.caseInsensitive])
                case .caseSensitive: return left.compare(right, options: [.literal])
                }
            }
            let valueComparison: ComparisonResult
            switch descriptor.key {
            case .name:
                valueComparison = stringCompare(lhs.displayName, rhs.displayName)
            case .extension:
                valueComparison = stringCompare(lhs.fileExtension, rhs.fileExtension)
            case .kind:
                valueComparison = stringCompare(lhs.typeDescription, rhs.typeDescription)
            case .size:
                valueComparison = lhs.size == rhs.size ? .orderedSame : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
            case .modified: valueComparison = compare(lhs.modificationDate, rhs.modificationDate)
            case .created: valueComparison = compare(lhs.creationDate, rhs.creationDate)
            case .added: valueComparison = compare(lhs.addedDate, rhs.addedDate)
            case .accessed: valueComparison = compare(lhs.accessDate, rhs.accessDate)
            }
            let nameComparison = stringCompare(lhs.displayName, rhs.displayName)
            let comparison = valueComparison != .orderedSame ? valueComparison
                : (nameComparison != .orderedSame ? nameComparison : lhs.url.path.compare(rhs.url.path, options: [.literal]))
            return descriptor.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    /// Missing metadata is explicit and consistently precedes present values.
    private static func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (left?, right?): return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        }
    }
}

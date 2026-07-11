import AppKit
import Foundation
import UniformTypeIdentifiers

protocol FileSystemServicing {
    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> [FileItem]
}

final class FileSystemService: FileSystemServicing {
    private let fileManager: FileManager
    private let accessPolicy: SandboxFileAccessPolicy

    init(fileManager: FileManager = .default, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileManager = fileManager
        self.accessPolicy = accessPolicy
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> [FileItem] {
        try accessPolicy.validateAccess(to: url)
        return try await accessPolicy.withAccess(to: [url]) {
            try await Task.detached(priority: .userInitiated) {
                try self.accessPolicy.validateAccess(to: url)
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
                .localizedTypeDescriptionKey,
                .contentTypeKey,
                .isPackageKey
            ]
            let urls = try self.fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: includingHidden ? [] : [.skipsHiddenFiles]
            )

            let items = urls.compactMap { child -> FileItem? in
                guard !Task.isCancelled else { return nil }
                do {
                    return try self.fileItem(for: child)
                } catch {
                    return nil
                }
            }

                return Self.sorted(items, descriptor: sort)
            }.value
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
            .localizedTypeDescriptionKey,
            .contentTypeKey,
            .isPackageKey
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
            posixPermissions: permissions,
            owner: owner,
            group: group,
            typeDescription: typeDescription,
            localizedTypeDescription: typeDescription,
            icon: .fileIcon(for: url)
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
            return "Alias"
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
            if lhs.isDirectory != rhs.isDirectory {
                // Keep folders grouped before files regardless of ascending/descending order.
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison: ComparisonResult
            switch descriptor.key {
            case .name:
                comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            case .kind:
                let kindComparison = lhs.typeDescription.localizedStandardCompare(rhs.typeDescription)
                comparison = kindComparison == .orderedSame
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName)
                    : kindComparison
            case .size:
                comparison = lhs.size == rhs.size
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName)
                    : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
            case .modified:
                let left = lhs.modificationDate ?? .distantPast
                let right = rhs.modificationDate ?? .distantPast
                comparison = left == right
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName)
                    : (left < right ? .orderedAscending : .orderedDescending)
            }
            return descriptor.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}

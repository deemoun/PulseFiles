import AppKit
import Foundation

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
        return try await Task.detached(priority: .userInitiated) {
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
            localizedTypeDescription: values.localizedTypeDescription ?? (isDirectory ? "Folder" : "File"),
            icon: .fileIcon(for: url)
        )
    }

    private func measuredSize(for url: URL, isDirectory: Bool, isSymbolicLink: Bool) -> Int64 {
        if isDirectory && !isSymbolicLink {
            return directorySize(at: url)
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

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileSizeKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            guard !Task.isCancelled else { break }
            let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileSizeKey, .fileSizeKey])
            if values?.isDirectory == true && values?.isSymbolicLink != true {
                continue
            }
            total += measuredSize(for: childURL, isDirectory: false, isSymbolicLink: values?.isSymbolicLink == true)
        }
        return total
    }

    static func sorted(_ items: [FileItem], descriptor: FileSortDescriptor) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let ordered: Bool
            switch descriptor.key {
            case .name:
                ordered = lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            case .size:
                ordered = lhs.size == rhs.size
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    : lhs.size < rhs.size
            case .modified:
                let left = lhs.modificationDate ?? .distantPast
                let right = rhs.modificationDate ?? .distantPast
                ordered = left == right
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    : left < right
            }
            return descriptor.ascending ? ordered : !ordered
        }
    }
}

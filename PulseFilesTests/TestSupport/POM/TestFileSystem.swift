// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
@testable import PulseFiles

final class TestFileSystem: FileSystemServicing {
    private var itemsByDirectory: [URL: [FileItem]]
    private(set) var requests: [(url: URL, includingHidden: Bool, sort: FileSortDescriptor)] = []
    private var errorsByDirectory: [URL: Error] = [:]
    private var itemReadFailuresByDirectory: [URL: [DirectoryItemReadFailure]] = [:]
    private var metadataByDirectory: [URL: DirectorySnapshotMetadata] = [:]
    private var metadataErrorsByDirectory: [URL: Error] = [:]

    init(itemsByDirectory: [URL: [FileItem]] = [:]) {
        self.itemsByDirectory = itemsByDirectory
    }

    func setItems(_ items: [FileItem], for directory: URL) {
        itemsByDirectory[directory] = items
    }

    func setError(_ error: Error, for directory: URL) {
        errorsByDirectory[directory] = error
    }

    func setItemReadFailures(_ failures: [DirectoryItemReadFailure], for directory: URL) {
        itemReadFailuresByDirectory[directory] = failures
    }

    func setMetadata(_ metadata: DirectorySnapshotMetadata, for directory: URL) {
        metadataByDirectory[directory] = metadata
    }

    func setMetadataError(_ error: Error, for directory: URL) {
        metadataErrorsByDirectory[directory] = error
    }

    func contentsOfDirectory(at url: URL, includingHidden: Bool, sort: FileSortDescriptor) async throws -> DirectoryContentsResult {
        requests.append((url: url, includingHidden: includingHidden, sort: sort))
        if let error = errorsByDirectory[url] {
            throw error
        }
        let items = itemsByDirectory[url, default: []]
        let visibleItems = includingHidden ? items : items.filter { !$0.isHidden }
        return DirectoryContentsResult(
            items: FileSystemService.sorted(visibleItems, descriptor: sort),
            itemReadFailures: itemReadFailuresByDirectory[url, default: []]
        )
    }

    func directorySnapshotMetadata(at url: URL) async throws -> DirectorySnapshotMetadata {
        if let error = metadataErrorsByDirectory[url] { throw error }
        return metadataByDirectory[url] ?? DirectorySnapshotMetadata(resourceIdentifier: url.path, changeDate: .distantPast)
    }

    static func item(
        named name: String,
        in directory: URL,
        isDirectory: Bool = false,
        size: Int64 = 0,
        modified: Date? = nil
    ) -> FileItem {
        let url = directory.appendingPathComponent(name, isDirectory: isDirectory)
        return FileItem(
            url: url,
            filename: name,
            displayName: name,
            fileExtension: url.pathExtension,
            fileType: isDirectory ? .folder : .file,
            isDirectory: isDirectory,
            isSymbolicLink: false,
            isHidden: name.hasPrefix("."),
            size: size,
            creationDate: nil,
            modificationDate: modified,
            posixPermissions: nil,
            owner: nil,
            group: nil,
            typeDescription: isDirectory ? "Folder" : "File",
            localizedTypeDescription: isDirectory ? "Folder" : "File",
            iconKey: FileIconKey(fileType: isDirectory ? .folder : .file, fileExtension: url.pathExtension)
        )
    }
}

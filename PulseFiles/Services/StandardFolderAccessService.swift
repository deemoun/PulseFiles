// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum StandardFolder: String, CaseIterable {
    case desktop
    case documents
    case downloads

    package var searchPathDirectory: FileManager.SearchPathDirectory {
        switch self {
        case .desktop: return .desktopDirectory
        case .documents: return .documentDirectory
        case .downloads: return .downloadsDirectory
        }
    }

    package var title: String {
        switch self {
        case .desktop: return "Desktop".localized
        case .documents: return "Documents".localized
        case .downloads: return "Downloads".localized
        }
    }
}

package enum StandardFolderAccessState: Equatable {
    case accessible
    case deniedOrUnavailable
    case requiresSystemSettingsReview
    case blockedByExperimentalSandbox
}

/// Resolves protected user folders and performs the small read that lets macOS
/// evaluate Files & Folders consent. It deliberately does not persist a grant:
/// TCC decisions and security-scoped folder bookmarks are separate capabilities.
package final class StandardFolderAccessService {
    package typealias URLResolver = (FileManager.SearchPathDirectory) -> URL?
    package typealias DirectoryReader = (URL) throws -> Void

    private let accessPolicy: SandboxFileAccessPolicy
    private let urlResolver: URLResolver
    private let directoryReader: DirectoryReader

    package init(
        accessPolicy: SandboxFileAccessPolicy = .current,
        urlResolver: @escaping URLResolver = { FileManager.default.urls(for: $0, in: .userDomainMask).first },
        directoryReader: @escaping DirectoryReader = { url in
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        }
    ) {
        self.accessPolicy = accessPolicy
        self.urlResolver = urlResolver
        self.directoryReader = directoryReader
    }

    package func url(for folder: StandardFolder) -> URL? {
        urlResolver(folder.searchPathDirectory)?.standardizedFileURL
    }

    package func requestAccess(for folder: StandardFolder) -> StandardFolderAccessState {
        guard let url = url(for: folder) else { return .deniedOrUnavailable }
        guard accessPolicy.canAttemptProtectedFolderAccess(url) else { return .blockedByExperimentalSandbox }

        do {
            try accessPolicy.withAccess(to: [url]) { try directoryReader(url) }
            return .accessible
        } catch {
            return Self.state(for: error)
        }
    }

    package static func state(for error: Error) -> StandardFolderAccessState {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileReadNoPermission.rawValue || nsError.code == CocoaError.fileWriteNoPermission.rawValue {
            return .requiresSystemSettingsReview
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == POSIXErrorCode.EACCES.rawValue || nsError.code == POSIXErrorCode.EPERM.rawValue {
            return .requiresSystemSettingsReview
        }
        return .deniedOrUnavailable
    }
}

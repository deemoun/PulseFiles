// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Deterministic classification for URLs received through macOS open events.
///
/// The app advertises folder support only. Every received URL is nevertheless
/// validated so that unregistered files or malformed automation requests cannot
/// bypass the same access policy used by the panes.
struct OpenEventRoutingResult: Equatable {
    let firstAcceptedFolder: URL?
    let acceptedFolderCount: Int
    let ignoredFileCount: Int
    let deniedURLCount: Int

    static let empty = OpenEventRoutingResult(
        firstAcceptedFolder: nil,
        acceptedFolderCount: 0,
        ignoredFileCount: 0,
        deniedURLCount: 0
    )
}

enum OpenEventRouter {
    /// Processes URLs in their received order. All URLs are validated; only
    /// the first accessible folder is returned for navigation. Files, later
    /// folders, non-file URLs, and inaccessible URLs leave existing panes
    /// unchanged. This prevents a single Finder request from unexpectedly
    /// navigating both panes or launching arbitrary files.
    static func route(
        _ urls: [URL],
        accessPolicy: SandboxFileAccessPolicy,
        probe: any FileSystemProbing,
        deadline: Duration = .milliseconds(250)
    ) async -> OpenEventRoutingResult {
        var firstAcceptedFolder: URL?
        var acceptedFolderCount = 0
        var ignoredFileCount = 0
        var deniedURLCount = 0

        for url in urls {
            guard url.isFileURL else {
                deniedURLCount += 1
                continue
            }

            do {
                let isDirectory = try await accessPolicy.withValidatedAccess(to: url) {
                    async let existence = probe.exists(url, deadline: deadline)
                    async let directory = probe.isDirectory(url, deadline: deadline)
                    guard case .value(true) = await existence,
                          case .value(let value) = await directory else { throw CocoaError(.fileReadUnknown) }
                    return value
                }
                guard isDirectory else {
                    ignoredFileCount += 1
                    continue
                }
            } catch {
                deniedURLCount += 1
                continue
            }

            acceptedFolderCount += 1
            if firstAcceptedFolder == nil {
                firstAcceptedFolder = url
            }
        }

        return OpenEventRoutingResult(
            firstAcceptedFolder: firstAcceptedFolder,
            acceptedFolderCount: acceptedFolderCount,
            ignoredFileCount: ignoredFileCount,
            deniedURLCount: deniedURLCount
        )
    }
}

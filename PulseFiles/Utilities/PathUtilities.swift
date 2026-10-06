// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

package enum PathUtilities {
    /// Presentation only: retain the original URL for access and navigation.
    package static func hasProtectedRootNamespace(_ url: URL) -> Bool {
        let components = url.pathComponents
        return url.isFileURL && components.count >= 2 && components[1] == ".nofollow"
            && (components.count > 2 || url.hasDirectoryPath)
    }

    package static func displayPath(for url: URL, homeDirectory: String? = nil) -> String {
        var path = url.path
        if hasProtectedRootNamespace(url) {
            path = String(path.dropFirst("/.nofollow".count))
            if path.isEmpty { path = "/" }
        }
        if let homeDirectory, homeDirectory != "/" {
            if path == homeDirectory { return "~" }
            if path.hasPrefix(homeDirectory + "/") {
                return "~" + path.dropFirst(homeDirectory.count)
            }
        }
        return path
    }

    package static func shellEscaped(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    package static func relativePath(from root: URL, to url: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let targetComponents = url.standardizedFileURL.pathComponents
        let common = zip(rootComponents, targetComponents).prefix { $0 == $1 }.count
        let up = Array(repeating: "..", count: rootComponents.count - common)
        let down = targetComponents.dropFirst(common)
        let parts = up + down
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}

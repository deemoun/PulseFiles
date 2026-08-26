// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

package enum PathUtilities {
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

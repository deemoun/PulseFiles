// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

package enum FilePathComparison {
    package static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    package static func isSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    package static func isSameOrDescendant(_ candidate: URL, ofDirectory directory: URL) -> Bool {
        let candidatePath = normalizedPath(candidate)
        let directoryPath = normalizedPath(directory)
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }

    package static func firstDirectoryContaining(
        _ candidate: URL,
        among sources: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        for source in sources {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if isSameOrDescendant(candidate, ofDirectory: source) {
                return source
            }
        }
        return nil
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// AppKit-facing request value shared by features that ask the composition root
/// to select and authorize a directory.
package struct FolderSelectionRequest {
    package let prompt: String
    package let message: String?
    package let initialDirectory: URL?
    package let acceptsExistingAccessibleURL: Bool
    package weak var presentingWindow: NSWindow?

    package init(prompt: String, message: String? = nil, initialDirectory: URL? = nil, acceptsExistingAccessibleURL: Bool = true, presentingWindow: NSWindow? = nil) {
        self.prompt = prompt
        self.message = message
        self.initialDirectory = initialDirectory
        self.acceptsExistingAccessibleURL = acceptsExistingAccessibleURL
        self.presentingWindow = presentingWindow
    }
}

package enum FolderSelectionFailure: Error {
    case cancelled
    case grant(Error)
    case rejected(Error)
}

@MainActor
package protocol AuthorizedFolderSelecting: AnyObject {
    func selectFolder(for request: FolderSelectionRequest, completion: @escaping (Result<URL, FolderSelectionFailure>) -> Void)
    func presentFailure(_ failure: FolderSelectionFailure, in window: NSWindow?)
}

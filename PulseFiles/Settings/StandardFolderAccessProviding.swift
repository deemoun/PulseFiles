// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

/// Injectable boundary used by the settings UI when requesting access to a
/// macOS-protected standard folder.
package protocol StandardFolderAccessProviding: AnyObject {
    func requestAccess(for folder: StandardFolder) -> StandardFolderAccessState
}

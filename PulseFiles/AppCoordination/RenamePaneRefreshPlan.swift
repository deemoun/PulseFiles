// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesUtilities

/// Separates panes needing a targeted rename refresh from panes that can use
/// the normal operation refresh, avoiding a competing selection reload.
package struct RenamePaneRefreshPlan {
    package let renamedPaneIndexes: [Int]
    package let genericRefreshPaneIndexes: [Int]

    package init(currentDirectories: [URL], sourceURL: URL) {
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let renamedIndexes = currentDirectories.indices.filter {
            FilePathComparison.isSamePath(currentDirectories[$0], sourceDirectory)
        }
        renamedPaneIndexes = renamedIndexes
        genericRefreshPaneIndexes = currentDirectories.indices.filter {
            !renamedIndexes.contains($0)
        }
    }
}

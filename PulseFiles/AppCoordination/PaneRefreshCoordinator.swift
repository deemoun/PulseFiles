// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
import PulseFilesUtilities

/// Value-only refresh decisions made after filesystem operations. The caller
/// remains responsible for translating pane indexes into owned pane controllers.
package struct PaneRefreshRoute: Equatable, Sendable {
    package struct TargetedReload: Equatable, Sendable {
        package let paneIndexes: [Int]
        package let selectionURL: URL

        package init(paneIndexes: [Int], selectionURL: URL) {
            self.paneIndexes = paneIndexes
            self.selectionURL = selectionURL
        }
    }

    package let genericPaneIndexes: [Int]
    package let targetedReload: TargetedReload?
    package let restoresFocusedPane: Bool

    package init(genericPaneIndexes: [Int], targetedReload: TargetedReload? = nil, restoresFocusedPane: Bool = false) {
        self.genericPaneIndexes = genericPaneIndexes
        self.targetedReload = targetedReload
        self.restoresFocusedPane = restoresFocusedPane
    }
}

/// Centralizes the pane invalidation policy without importing AppKit or
/// retaining pane controllers.
package struct PaneRefreshCoordinator: Sendable {
    package init() {}

    package func afterRename(currentDirectories: [URL], sourceURL: URL, result: FileOperationResult) -> PaneRefreshRoute {
        guard let renamedURL = result.completedItems.first else {
            return PaneRefreshRoute(genericPaneIndexes: Array(currentDirectories.indices))
        }
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let targeted = currentDirectories.indices.filter {
            FilePathComparison.isSamePath(currentDirectories[$0], sourceDirectory)
        }
        let generic = currentDirectories.indices.filter { !targeted.contains($0) }
        return PaneRefreshRoute(
            genericPaneIndexes: generic,
            targetedReload: targeted.isEmpty ? nil : .init(paneIndexes: targeted, selectionURL: renamedURL),
            restoresFocusedPane: !targeted.isEmpty
        )
    }

    package func afterTransfer(paneCount: Int) -> PaneRefreshRoute {
        PaneRefreshRoute(genericPaneIndexes: Array(0..<max(0, paneCount)))
    }

    package func afterDelete(paneCount: Int) -> PaneRefreshRoute { afterTransfer(paneCount: paneCount) }
    package func afterRecovery(paneCount: Int) -> PaneRefreshRoute { afterTransfer(paneCount: paneCount) }
}

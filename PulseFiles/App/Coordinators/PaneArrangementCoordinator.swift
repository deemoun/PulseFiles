// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesAppCoordination
import PulseFilesModels

final class PaneArrangementCoordinator: NSObject, NSSplitViewDelegate {
    struct Inputs {
        let root: NSSplitView
        let content: NSSplitView
        let panes: NSSplitView
        let paneView: (PaneID) -> NSView
        let sidebarInstalled: () -> Bool
    }

    private let inputs: Inputs
    private let persistSidebarWidth: () -> Void

    init(inputs: Inputs, persistSidebarWidth: @escaping () -> Void) {
        self.inputs = inputs
        self.persistSidebarWidth = persistSidebarWidth
    }

    func installAsDelegate() {
        inputs.root.delegate = self
        inputs.content.delegate = self
        inputs.panes.delegate = self
    }

    func apply(_ route: PaneArrangementRoute) {
        inputs.panes.arrangedSubviews.forEach {
            inputs.panes.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        route.visiblePanes.forEach { inputs.panes.addArrangedSubview(inputs.paneView($0)) }
        inputs.panes.superview?.layoutSubtreeIfNeeded()
        if route.hasOppositePane, inputs.panes.bounds.width > 0 {
            inputs.panes.setPosition(max(260, inputs.panes.bounds.width / 2), ofDividerAt: 0)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === inputs.root { return 620 }
        if splitView === inputs.panes || splitView === inputs.content { return 220 + (splitView === inputs.panes ? 40 : 0) }
        return proposed
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === inputs.root {
            return inputs.sidebarInstalled() ? max(620, splitView.bounds.width - 220) : splitView.bounds.width
        }
        if splitView === inputs.panes { return max(260, splitView.bounds.width - 260) }
        if splitView === inputs.content { return max(220, splitView.bounds.height - 120) }
        return proposed
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard notification.object as? NSSplitView === inputs.root else { return }
        persistSidebarWidth()
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns sidebar installation and its persisted split position.
@MainActor
final class SidebarLayoutCoordinator {
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let contentMinimumWidth: CGFloat
    private(set) var isInstalled = false

    init(minimumWidth: CGFloat = 220, maximumWidth: CGFloat = 340, contentMinimumWidth: CGFloat = 620) {
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.contentMinimumWidth = contentMinimumWidth
    }

    func install(_ view: NSView, in splitView: NSSplitView, constraints: [NSLayoutConstraint]) {
        guard !isInstalled else { return }
        view.isHidden = false
        constraints.forEach { $0.isActive = true }
        splitView.addArrangedSubview(view)
        isInstalled = true
    }

    func remove(_ view: NSView, from splitView: NSSplitView, constraints: [NSLayoutConstraint]) {
        guard isInstalled else { return }
        constraints.forEach { $0.isActive = false }
        splitView.removeArrangedSubview(view)
        view.removeFromSuperview()
        view.isHidden = true
        isInstalled = false
    }

    func clampedWidth(_ width: CGFloat) -> CGFloat { min(max(width, minimumWidth), maximumWidth) }

    func applyPersistedWidth(_ width: Double, sidebarView: NSView, in splitView: NSSplitView) {
        guard isInstalled, splitView.arrangedSubviews.count > 1 else { return }
        splitView.setPosition(max(contentMinimumWidth, splitView.bounds.width - clampedWidth(CGFloat(width))), ofDividerAt: 0)
    }

    func persistedWidth(sidebarView: NSView, in splitView: NSSplitView) -> Double? {
        guard isInstalled, splitView.arrangedSubviews.count > 1, splitView.bounds.width > 0 else { return nil }
        return Double(clampedWidth(sidebarView.frame.width))
    }
}

/// Owns terminal view and session lifecycle as one indivisible layout operation.
@MainActor
final class TerminalLayoutCoordinator {
    private(set) var isInstalled = false

    func install(_ terminal: TerminalViewController, in splitView: NSSplitView, heightConstraint: inout NSLayoutConstraint?) {
        guard !isInstalled else { return }
        splitView.addArrangedSubview(terminal.view)
        if heightConstraint == nil { heightConstraint = terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120) }
        heightConstraint?.isActive = true
        isInstalled = true
        terminal.startSessionIfAllowed()
    }

    func remove(_ terminal: TerminalViewController, from splitView: NSSplitView, heightConstraint: NSLayoutConstraint?) {
        guard isInstalled else { return }
        terminal.resetSession()
        heightConstraint?.isActive = false
        splitView.removeArrangedSubview(terminal.view)
        terminal.view.removeFromSuperview()
        isInstalled = false
    }
}

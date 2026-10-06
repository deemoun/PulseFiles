// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesPresentationSupport
import PulseFilesServices
import PulseFilesSettings
import PulseFilesTerminal

/// Owns sidebar installation and its persisted split position.
@MainActor
final class SidebarLayoutCoordinator {
    struct Inputs {
        let settings: SettingsService
        let sidebarView: NSView
        let splitView: NSSplitView
        let constraints: [NSLayoutConstraint]
        let layout: () -> Void
        let updateToolbar: () -> Void
    }

    enum VisibilityResult: Equatable { case unchanged, installed, removed }
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

    @discardableResult
    func setVisible(_ visible: Bool, inputs: Inputs) -> VisibilityResult {
        guard visible != isInstalled else {
            inputs.settings.isSidebarVisible = visible
            inputs.updateToolbar()
            return .unchanged
        }
        if visible {
            install(inputs.sidebarView, in: inputs.splitView, constraints: inputs.constraints)
        } else {
            if let width = persistedWidth(sidebarView: inputs.sidebarView, in: inputs.splitView) {
                inputs.settings.sidebarWidth = width
            }
            remove(inputs.sidebarView, from: inputs.splitView, constraints: inputs.constraints)
        }
        inputs.settings.isSidebarVisible = visible
        inputs.layout()
        if visible { applyPersistedWidth(inputs.settings.sidebarWidth, sidebarView: inputs.sidebarView, in: inputs.splitView) }
        inputs.updateToolbar()
        return visible ? .installed : .removed
    }
}

/// Owns terminal view and session lifecycle as one indivisible layout operation.
@MainActor
final class TerminalLayoutCoordinator {
    private var widthConstraint: NSLayoutConstraint?
    struct Inputs {
        let settings: SettingsService
        let terminal: TerminalViewController
        let splitView: NSSplitView
        let activeDirectory: URL
        let accessPolicy: SandboxFileAccessPolicy
        let focusPane: () -> Void
        let presentDisabledWarning: () -> Void
        let presentFirstUseWarning: () -> Void
        let layout: () -> Void
    }

    enum ToggleResult: Equatable { case shown, hidden, disabled }
    private(set) var isInstalled = false

    func install(_ terminal: TerminalViewController, in splitView: NSSplitView, heightConstraint: inout NSLayoutConstraint?) {
        guard !isInstalled else { return }
        terminal.view.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(terminal.view)
        widthConstraint = terminal.view.widthAnchor.constraint(equalTo: splitView.widthAnchor)
        widthConstraint?.isActive = true
        if heightConstraint == nil { heightConstraint = terminal.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120) }
        heightConstraint?.isActive = true
        isInstalled = true
        terminal.startSessionIfAllowed()
    }

    func remove(_ terminal: TerminalViewController, from splitView: NSSplitView, heightConstraint: NSLayoutConstraint?) {
        guard isInstalled else { return }
        terminal.resetSession()
        widthConstraint?.isActive = false
        widthConstraint = nil
        heightConstraint?.isActive = false
        splitView.removeArrangedSubview(terminal.view)
        terminal.view.removeFromSuperview()
        isInstalled = false
    }

    func toggle(
        inputs: Inputs,
        presentation: TerminalPresentationCoordinator,
        heightConstraint: inout NSLayoutConstraint?
    ) -> ToggleResult {
        presentation.synchronize(installed: isInstalled)
        switch presentation.toggle(isEnabled: inputs.settings.experimentalTerminalEnabled) {
        case .hide:
            remove(inputs.terminal, from: inputs.splitView, heightConstraint: heightConstraint)
            inputs.settings.isTerminalVisible = false
            inputs.focusPane()
            return .hidden
        case .disabled:
            inputs.presentDisabledWarning()
            return .disabled
        case .show:
            inputs.presentFirstUseWarning()
            install(inputs.terminal, in: inputs.splitView, heightConstraint: &heightConstraint)
            inputs.settings.isTerminalVisible = true
            inputs.terminal.suggestedWorkingDirectory = presentation.workingDirectory(
                activePaneURL: inputs.activeDirectory, accessPolicy: inputs.accessPolicy
            )
            inputs.layout()
            inputs.splitView.setPosition(max(220, inputs.splitView.bounds.height - 180), ofDividerAt: 0)
            inputs.terminal.focusCommandField()
            return .shown
        }
    }
}

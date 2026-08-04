import AppKit

/// Owns the mechanics of adding/removing the sidebar child view. The composition
/// controller still owns WindowLayoutController, which records shared state.
@MainActor
final class SidebarLayoutCoordinator {
    private(set) var isInstalled = false

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
}

@MainActor
final class TerminalLayoutCoordinator {
    private(set) var isInstalled = false

    func install(_ view: NSView, in splitView: NSSplitView, heightConstraint: inout NSLayoutConstraint?) {
        guard !isInstalled else { return }
        splitView.addArrangedSubview(view)
        if heightConstraint == nil { heightConstraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120) }
        heightConstraint?.isActive = true
        isInstalled = true
    }

    func remove(_ view: NSView, from splitView: NSSplitView, heightConstraint: NSLayoutConstraint?) {
        guard isInstalled else { return }
        heightConstraint?.isActive = false
        splitView.removeArrangedSubview(view)
        view.removeFromSuperview()
        isInstalled = false
    }
}

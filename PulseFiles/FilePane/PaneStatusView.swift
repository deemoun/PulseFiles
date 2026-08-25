import AppKit

package final class PaneStatusView: NSVisualEffectView {
    struct Action {
        let title: String
        let accessibilityLabel: String
        let handler: () -> Void
    }

    private let label = NSTextField(labelWithString: "")
    private let actionStack = NSStackView()

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor.secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(actionStack)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    package func configure(items: [FileItem], selectedItems: [FileItem], isLoading: Bool, errorMessage: String?, partialRefreshFailure: DirectoryContentsReadError?, isPartialRefreshRetryScheduled: Bool, volumeStatus: VolumeStatusPresentation, actions: [Action] = []) {
        configureActions(actions)
        if isLoading {
            label.stringValue = partialRefreshFailure == nil
                ? "Loading...".localized
                : "Refreshing incomplete folder listing...".localized
            label.textColor = partialRefreshFailure == nil ? NSColor.secondaryLabelColor : .systemOrange
            return
        }
        if let partialRefreshFailure {
            let retrySuffix = isPartialRefreshRetryScheduled ? " Retrying shortly.".localized : ""
            label.stringValue = "Folder listing may be incomplete: %@%@".localized(with: partialRefreshFailure.localizedDescription, retrySuffix)
            label.textColor = .systemOrange
            return
        }
        if let errorMessage {
            label.stringValue = "Unable to read folder: %@".localized(with: errorMessage)
            label.textColor = .systemOrange
            return
        }
        let selectedSize = selectedItems.reduce(Int64(0)) { $0 + $1.size }
        let folderCount = items.filter(\.isDirectory).count
        let size = selectedItems.isEmpty ? "" : " · %@ selected".localized(with: FileSizeFormatter.string(fromByteCount: selectedSize))
        let itemSummary = "%d items · %d folders · %d selected%@".localized(with: items.count, folderCount, selectedItems.count, size)
        label.stringValue = "\(itemSummary) · \(volumeStatus.detail)"
        label.textColor = volumeStatus.isWarning ? .systemOrange : NSColor.secondaryLabelColor
    }

    private func configureActions(_ actions: [Action]) {
        actionStack.arrangedSubviews.forEach { view in
            actionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actions.forEach { action in
            let button = ClosureButton(title: action.title, handler: action.handler)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            button.setAccessibilityLabel(action.accessibilityLabel)
            actionStack.addArrangedSubview(button)
        }
    }
}

package final class PaneContentOverlayView: NSVisualEffectView {
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let actionStack = NSStackView()
    private var passesEmptyStateEventsThrough = false

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = 12

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, titleLabel, detailLabel, actionStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    package override func hitTest(_ point: NSPoint) -> NSView? {
        passesEmptyStateEventsThrough ? nil : super.hitTest(point)
    }

    package func configure(paneID: PaneID, isLoading: Bool, visibleItems: [FileItem], errorMessage: String?, actions: [PaneStatusView.Action]) {
        setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.contentOverlay(for: paneID))
        titleLabel.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.contentOverlayTitle(for: paneID))
        spinner.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.loadingIndicator(for: paneID))
        configureActions(actions, paneID: paneID)

        if isLoading {
            passesEmptyStateEventsThrough = false
            isHidden = false
            spinner.startAnimation(nil)
            spinner.isHidden = false
            titleLabel.stringValue = "Loading...".localized
            detailLabel.stringValue = ""
            actionStack.isHidden = true
            return
        }

        spinner.stopAnimation(nil)
        spinner.isHidden = true

        if let errorMessage, !errorMessage.isEmpty {
            passesEmptyStateEventsThrough = false
            isHidden = false
            titleLabel.stringValue = "Unable to read folder".localized
            detailLabel.stringValue = errorMessage
            actionStack.isHidden = actions.isEmpty
            return
        }

        if visibleItems.isEmpty {
            // An empty folder's synthetic parent row is obscured by this
            // overlay. Keep pointer events here whenever a parent-navigation
            // action is available so the button can be used.
            passesEmptyStateEventsThrough = actions.isEmpty
            isHidden = false
            titleLabel.stringValue = "This folder is empty".localized
            detailLabel.stringValue = ""
            actionStack.isHidden = actions.isEmpty
            return
        }

        passesEmptyStateEventsThrough = false
        isHidden = true
        titleLabel.stringValue = ""
        detailLabel.stringValue = ""
        actionStack.isHidden = true
    }

    private func configureActions(_ actions: [PaneStatusView.Action], paneID: PaneID) {
        actionStack.arrangedSubviews.forEach { view in
            actionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actions.enumerated().forEach { index, action in
            let button = ClosureButton(title: action.title, handler: action.handler)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 12)
            button.setAccessibilityLabel(action.accessibilityLabel)
            button.setAccessibilityIdentifier(AccessibilityIdentifiers.Pane.contentOverlayAction(for: paneID, index: index))
            actionStack.addArrangedSubview(button)
        }
    }
}

private final class ClosureButton: NSButton {
    private let handler: () -> Void

    package init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(performAction)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func performAction() {
        handler()
    }
}

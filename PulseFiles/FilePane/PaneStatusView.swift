import AppKit

final class PaneStatusView: NSVisualEffectView {
    struct Action {
        let title: String
        let accessibilityLabel: String
        let handler: () -> Void
    }

    private let label = NSTextField(labelWithString: "")
    private let actionStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        label.font = .systemFont(ofSize: 12)
        label.textColor = LiquidGlassStyle.secondaryLabel
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

    func configure(items: [FileItem], selectedItems: [FileItem], isLoading: Bool, errorMessage: String?, actions: [Action] = []) {
        configureActions(actions)
        if isLoading {
            label.stringValue = "Loading...".localized
            return
        }
        if let errorMessage {
            label.stringValue = "Unable to read folder: %@".localized(with: errorMessage)
            return
        }
        let selectedSize = selectedItems.reduce(Int64(0)) { $0 + $1.size }
        let folderCount = items.filter(\.isDirectory).count
        let size = selectedItems.isEmpty ? "" : " · %@ selected".localized(with: FileSizeFormatter.string(fromByteCount: selectedSize))
        label.stringValue = "%d items · %d folders · %d selected%@".localized(with: items.count, folderCount, selectedItems.count, size)
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

private final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
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

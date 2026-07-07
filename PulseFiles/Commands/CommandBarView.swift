import AppKit

final class CommandBarView: NSVisualEffectView {
    var onAction: ((CommandBarAction) -> Void)?

    private let stack = NSStackView()
    private let operationStatusLabel = NSTextField(labelWithString: "")
    private let cancelOperationButton = NSButton(title: "", target: nil, action: nil)
    private var isShowingShiftActions = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        blendingMode = .withinWindow
        state = .active
        setAccessibilityIdentifier(AccessibilityIdentifiers.CommandBar.panel)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func build() {
        stack.setAccessibilityIdentifier(AccessibilityIdentifiers.CommandBar.list)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        operationStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        operationStatusLabel.textColor = .secondaryLabelColor
        operationStatusLabel.alignment = .right
        operationStatusLabel.lineBreakMode = .byTruncatingMiddle
        operationStatusLabel.isHidden = true
        operationStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelOperationButton.title = "Cancel Operation".localized
        cancelOperationButton.target = self
        cancelOperationButton.action = #selector(cancelActiveOperation(_:))
        cancelOperationButton.identifier = NSUserInterfaceItemIdentifier(CommandBarAction.cancelOperation.rawValue)
        cancelOperationButton.setAccessibilityIdentifier("\(AccessibilityIdentifiers.CommandBar.field).cancelOperation")
        cancelOperationButton.toolTip = "Cancel the active file operation (Command-Period)".localized
        cancelOperationButton.setButtonType(.momentaryPushIn)
        cancelOperationButton.isHidden = true
        cancelOperationButton.isEnabled = false
        cancelOperationButton.translatesAutoresizingMaskIntoConstraints = false
        LiquidGlassStyle.applyButtonChrome(to: cancelOperationButton)

        addSubview(stack)
        addSubview(operationStatusLabel)
        addSubview(cancelOperationButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            operationStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12),
            operationStatusLabel.trailingAnchor.constraint(equalTo: cancelOperationButton.leadingAnchor, constant: -8),
            operationStatusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            operationStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),

            cancelOperationButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cancelOperationButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        reloadButtons()
    }

    func refreshAppearance() {
        material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        reloadButtons()
        LiquidGlassStyle.applyButtonChrome(to: cancelOperationButton)
    }

    func setShiftPressed(_ isShiftPressed: Bool) {
        guard isShowingShiftActions != isShiftPressed else { return }
        isShowingShiftActions = isShiftPressed
        reloadButtons()
    }

    func setOperationStatus(_ status: String) {
        operationStatusLabel.stringValue = status
        operationStatusLabel.toolTip = status
        operationStatusLabel.isHidden = status.isEmpty
        cancelOperationButton.isHidden = status.isEmpty
        cancelOperationButton.isEnabled = !status.isEmpty
    }

    func clearOperationStatus() {
        operationStatusLabel.stringValue = ""
        operationStatusLabel.toolTip = nil
        operationStatusLabel.isHidden = true
        cancelOperationButton.isHidden = true
        cancelOperationButton.isEnabled = false
    }

    private func reloadButtons() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let actions: [CommandBarAction] = [.rename, .view, .edit, .copy, .move, isShowingShiftActions ? .newFile : .newFolder, .delete]
        for action in actions {
            let button = NSButton(title: "\(action.shortcut)  \(action.title)", target: self, action: #selector(runAction(_:)))
            LiquidGlassStyle.applyButtonChrome(to: button)
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            button.setAccessibilityIdentifier("\(AccessibilityIdentifiers.CommandBar.field).\(action.rawValue)")
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = action.rawValue
            button.setButtonType(.momentaryPushIn)
            stack.addArrangedSubview(button)
        }
    }

    @objc private func cancelActiveOperation(_ sender: NSButton) {
        onAction?(.cancelOperation)
    }

    @objc private func runAction(_ sender: NSButton) {
        guard
            let value = sender.identifier?.rawValue,
            let action = CommandBarAction(rawValue: value)
        else { return }
        onAction?(action)
    }
}

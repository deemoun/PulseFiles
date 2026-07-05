import AppKit

final class CommandBarView: NSVisualEffectView {
    var onAction: ((CommandBarAction) -> Void)?

    private let stack = NSStackView()
    private let operationStatusLabel = NSTextField(labelWithString: "")
    private var isShowingShiftActions = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func build() {
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

        addSubview(stack)
        addSubview(operationStatusLabel)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: operationStatusLabel.leadingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            operationStatusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            operationStatusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            operationStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])

        reloadButtons()
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
    }

    func clearOperationStatus() {
        operationStatusLabel.stringValue = ""
        operationStatusLabel.toolTip = nil
        operationStatusLabel.isHidden = true
    }

    private func reloadButtons() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let actions: [CommandBarAction] = [.rename, .view, .edit, .copy, .move, isShowingShiftActions ? .newFile : .newFolder, .delete]
        for action in actions {
            let button = NSButton(title: "\(action.shortcut)  \(action.rawValue)", target: self, action: #selector(runAction(_:)))
            LiquidGlassStyle.applyButtonChrome(to: button)
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = action.rawValue
            button.setButtonType(.momentaryPushIn)
            stack.addArrangedSubview(button)
        }
    }

    @objc private func runAction(_ sender: NSButton) {
        guard
            let value = sender.identifier?.rawValue,
            let action = CommandBarAction(rawValue: value)
        else { return }
        onAction?(action)
    }
}

import AppKit

final class CommandBarView: NSVisualEffectView {
    var onAction: ((CommandBarAction) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .withinWindow
        state = .active
        build()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        for action in CommandBarAction.allCases {
            let button = NSButton(title: "\(action.shortcut)  \(action.rawValue)", target: self, action: #selector(runAction(_:)))
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
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

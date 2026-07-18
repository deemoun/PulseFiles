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
        stack.spacing = 10
        stack.distribution = .gravityAreas
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

    func setOperationProgress(_ progress: FileOperationProgress, operationName: String) {
        if progress.isPreparingTransfer {
            setOperationStatus("\(operationName): Preparing transfer…".localized)
            return
        }
        let itemDetail: String
        if let completed = progress.completedRecursiveItemCount,
           let total = progress.totalRecursiveItemCount {
            itemDetail = "\(completed)/\(total) items"
        } else {
            itemDetail = "\(progress.completedCount)/\(progress.totalCount) items"
        }

        let byteDetail: String
        if let completed = progress.completedByteCount,
           let total = progress.totalByteCount {
            let transferred = ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            if total > 0 {
                let percentage = min(100, Int((Double(completed) / Double(total) * 100).rounded()))
                byteDetail = "\(transferred)/\(totalText) (\(percentage)%)"
            } else {
                byteDetail = "\(transferred)/\(totalText)"
            }
        } else {
            byteDetail = "Calculating size…"
        }
        setOperationStatus("\(operationName): \(progress.currentItemName) (\(itemDetail) • \(byteDetail))")
    }

    func setTransientStatus(_ status: String) {
        operationStatusLabel.stringValue = status
        operationStatusLabel.toolTip = status
        operationStatusLabel.isHidden = status.isEmpty
        cancelOperationButton.isHidden = true
        cancelOperationButton.isEnabled = false
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
            let button = CommandBarActionButton(commandAction: action)
            button.target = self
            button.action = #selector(runAction(_:))
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(button)
            stack.setVisibilityPriority(action.commandBarVisibilityPriority, for: button)
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

private final class CommandBarActionButton: NSControl {
    private let commandAction: CommandBarAction
    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false { didSet { updateChrome() } }
    private var isPressing = false { didSet { updateChrome() } }

    init(commandAction: CommandBarAction) {
        self.commandAction = commandAction
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let titleWidth = titleLabel.intrinsicContentSize.width
        let keyWidth = keyLabel.intrinsicContentSize.width
        return NSSize(width: ceil(titleWidth + keyWidth + 28), height: 28)
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            updateChrome()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let shouldSend = isPressing && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressing = false
        if shouldSend {
            sendAction(action, to: target)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier(commandAction.rawValue)
        setAccessibilityIdentifier("\(AccessibilityIdentifiers.CommandBar.field).\(commandAction.rawValue)")
        toolTip = commandAction.localizedTooltip

        keyLabel.stringValue = commandAction.shortcut
        keyLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        keyLabel.alignment = .center
        keyLabel.lineBreakMode = .byClipping
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.stringValue = commandAction.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byClipping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(keyLabel)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateChrome()
    }

    private func updateChrome() {
        let destructive = commandAction.isDestructive
        let baseAlpha: CGFloat = LiquidGlassStyle.isEnabled ? 0.068 : 0.075
        let hoverBoost: CGFloat = isHovering ? 0.045 : 0
        let pressBoost: CGFloat = isPressing ? 0.06 : 0
        let fillAlpha = baseAlpha + hoverBoost + pressBoost
        let strokeAlpha = LiquidGlassStyle.isEnabled ? 0.14 : 0.11
        let textColor = destructive ? NSColor.systemRed : LiquidGlassStyle.label
        let keyFill = destructive
            ? NSColor.systemRed.withAlphaComponent(LiquidGlassStyle.isEnabled ? 0.13 : 0.10)
            : NSColor(calibratedWhite: 1, alpha: LiquidGlassStyle.isEnabled ? 0.10 : 0.08)

        layer?.backgroundColor = destructive
            ? NSColor.systemRed.withAlphaComponent(fillAlpha).cgColor
            : NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: fillAlpha).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = destructive
            ? NSColor.systemRed.withAlphaComponent(LiquidGlassStyle.isEnabled ? 0.28 : 0.22).cgColor
            : NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: strokeAlpha).cgColor

        keyLabel.textColor = destructive ? NSColor.systemRed : LiquidGlassStyle.secondaryLabel
        keyLabel.wantsLayer = true
        keyLabel.layer?.cornerRadius = 4
        keyLabel.layer?.cornerCurve = .continuous
        keyLabel.layer?.backgroundColor = keyFill.cgColor
        titleLabel.textColor = textColor
    }
}


extension CommandBarAction {
    var isDestructive: Bool {
        switch self {
        case .delete:
            return true
        case .rename, .view, .edit, .copy, .move, .newFolder, .newFile, .cancelOperation:
            return false
        }
    }

    var localizedTooltip: String {
        "\(title) (\(shortcut))"
    }

    var commandBarVisibilityPriority: NSStackView.VisibilityPriority {
        switch self {
        case .view, .copy, .move, .delete:
            return .mustHold
        case .rename, .edit, .newFolder, .newFile:
            return .detachOnlyIfNecessary
        case .cancelOperation:
            return .mustHold
        }
    }
}

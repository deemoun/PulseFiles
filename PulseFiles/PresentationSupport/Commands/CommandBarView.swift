// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesPresentationSupport
import PulseFilesWorkflows

package final class CommandBarView: NSVisualEffectView {
    package var onAction: ((CommandBarAction) -> Void)?

    private let stack = NSStackView()
    private let transientStatusLabel = NSTextField(labelWithString: "")
    private var isShowingShiftActions = false
    private var liquidGlassStyle: LiquidGlassStyle

    package init(style: LiquidGlassStyle) {
        liquidGlassStyle = style
        super.init(frame: .zero)
        material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
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

        transientStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        transientStatusLabel.textColor = .secondaryLabelColor
        transientStatusLabel.alignment = .right
        transientStatusLabel.lineBreakMode = .byTruncatingMiddle
        transientStatusLabel.isHidden = true
        transientStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(transientStatusLabel)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            transientStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12),
            transientStatusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            transientStatusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            transientStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])

        reloadButtons()
    }

    package func refreshAppearance(style: LiquidGlassStyle) {
        liquidGlassStyle = style
        material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        reloadButtons()
    }

    package func setShiftPressed(_ isShiftPressed: Bool) {
        guard isShowingShiftActions != isShiftPressed else { return }
        isShowingShiftActions = isShiftPressed
        reloadButtons()
    }

    package func setTransientStatus(_ status: String) {
        transientStatusLabel.stringValue = status
        transientStatusLabel.toolTip = status
        transientStatusLabel.isHidden = status.isEmpty
    }

    func clearOperationStatus() {
        transientStatusLabel.stringValue = ""
        transientStatusLabel.toolTip = nil
        transientStatusLabel.isHidden = true
    }

    private func reloadButtons() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let actions: [CommandBarAction] = [.rename, .view, .copy, .move, isShowingShiftActions ? .newFile : .newFolder, .delete]
        for action in actions {
            let button = CommandBarActionButton(commandAction: action, style: liquidGlassStyle)
            button.target = self
            button.action = #selector(runAction(_:))
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(button)
            stack.setVisibilityPriority(action.commandBarVisibilityPriority, for: button)
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

private final class CommandBarActionButton: NSControl {
    private let commandAction: CommandBarAction
    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false { didSet { updateChrome() } }
    private var isPressing = false { didSet { updateChrome() } }
    private let liquidGlassStyle: LiquidGlassStyle

    init(commandAction: CommandBarAction, style: LiquidGlassStyle) {
        self.commandAction = commandAction
        self.liquidGlassStyle = style
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
        let baseAlpha: CGFloat = liquidGlassStyle.isEnabled ? 0.068 : 0.075
        let hoverBoost: CGFloat = isHovering ? 0.045 : 0
        let pressBoost: CGFloat = isPressing ? 0.06 : 0
        let fillAlpha = baseAlpha + hoverBoost + pressBoost
        let strokeAlpha = liquidGlassStyle.isEnabled ? 0.14 : 0.11
        let textColor = destructive ? NSColor.systemRed : liquidGlassStyle.label
        let keyFill = destructive
            ? NSColor.systemRed.withAlphaComponent(liquidGlassStyle.isEnabled ? 0.13 : 0.10)
            : NSColor(calibratedWhite: 1, alpha: liquidGlassStyle.isEnabled ? 0.10 : 0.08)

        layer?.backgroundColor = destructive
            ? NSColor.systemRed.withAlphaComponent(fillAlpha).cgColor
            : NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: fillAlpha).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = destructive
            ? NSColor.systemRed.withAlphaComponent(liquidGlassStyle.isEnabled ? 0.28 : 0.22).cgColor
            : NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: strokeAlpha).cgColor

        keyLabel.textColor = destructive ? NSColor.systemRed : liquidGlassStyle.secondaryLabel
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
        case .rename, .batchRename, .createArchive, .extractArchive, .view, .copy, .move, .newFolder, .newFile, .cancelOperation, .newTab, .closeTab, .nextTab, .previousTab:
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
        case .rename, .batchRename, .createArchive, .extractArchive, .newFolder, .newFile, .newTab, .closeTab, .nextTab, .previousTab:
            return .detachOnlyIfNecessary
        case .cancelOperation:
            return .mustHold
        }
    }
}

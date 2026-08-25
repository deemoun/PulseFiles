import AppKit

final class SidebarInfoRowView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")

    init(info: SidebarInfoRow) {
        super.init(frame: .zero)
        setup(info: info)
    }

    required init?(coder: NSCoder) { nil }

    func setValue(_ value: String) {
        valueLabel.stringValue = value
        valueLabel.toolTip = value
    }

    private func setup(info: SidebarInfoRow) {
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: NSImage(systemSymbolName: info.symbol, accessibilityDescription: info.title) ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        imageView.contentTintColor = NSColor.secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: info.title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.stringValue = info.value
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = NSColor.labelColor
        valueLabel.alignment = .left
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.maximumNumberOfLines = 2
        valueLabel.toolTip = info.value
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, valueLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(textStack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 9),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }
}

final class SidebarDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class SidebarRowView: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateChrome() }
    }

    init(item: SidebarItem) {
        super.init(frame: .zero)
        setup(item: item)
    }

    required init?(coder: NSCoder) {
        nil
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
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let shouldOpen = bounds.contains(convert(event.locationInWindow, from: nil))
        highlight(false)
        if shouldOpen {
            sendAction(action, to: target)
        }
    }

    private func setup(item: SidebarItem) {
        wantsLayer = true
        layer?.cornerRadius = LiquidGlassStyle.compactCornerRadius
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: item.subtitle == nil ? 32 : 42).isActive = true

        imageView.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        imageView.contentTintColor = NSColor.secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.stringValue = item.subtitle ?? ""
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.isHidden = item.subtitle == nil
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.stringValue = item.badge.map(String.init) ?? ""
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = NSColor.secondaryLabelColor
        badgeLabel.alignment = .right
        badgeLabel.isHidden = item.badge == nil
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(textStack)
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 17),
            imageView.heightAnchor.constraint(equalToConstant: 17),

            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -8),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16)
        ])

        updateChrome()
    }

    private func highlight(_ active: Bool) {
        layer?.backgroundColor = (active ? NSColor.systemBlue.withAlphaComponent(0.08) : hoverFill).cgColor
    }

    private func updateChrome() {
        layer?.backgroundColor = hoverFill.cgColor
        layer?.borderWidth = isHovering ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private var hoverFill: NSColor {
        isHovering ? NSColor(calibratedWhite: 1, alpha: 0.07) : .clear
    }
}

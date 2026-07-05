import AppKit

final class SidebarViewController: NSViewController {
    var onOpenLocation: ((URL, Bool) -> Void)?

    fileprivate struct SidebarItem {
        let title: String
        let subtitle: String?
        let url: URL
        let symbol: String
        let group: String
        let badge: Int?

        init(title: String, subtitle: String? = nil, url: URL, symbol: String, group: String, badge: Int? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.url = url
            self.symbol = symbol
            self.group = group
            self.badge = badge
        }
    }

    private let recentLocations: RecentLocationService
    private let accessPolicy: SandboxFileAccessPolicy
    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    init(recentLocations: RecentLocationService, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.recentLocations = recentLocations
        self.accessPolicy = accessPolicy
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = .hudWindow
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
        LiquidGlassStyle.applyPanelChrome(to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScrollView()
        configureStack()
        rebuild()
        recentLocations.onChange = { [weak self] _ in self?.rebuild() }
    }

    func refresh() {
        rebuild()
    }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureStack() {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        addSectionIfNeeded("Favorites", items: favoriteItems())

        if ExperimentalFlags.restrictFileAccessToAppSandboxRoot {
            addSectionIfNeeded("Workspace", items: sandboxItems())
            addSandboxRestrictionNote()
        }

        addSectionIfNeeded("Devices & Locations", items: deviceItems())
        addSectionIfNeeded("Recent", items: recentItems())
    }

    private func favoriteItems() -> [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return accessibleItems([
            SidebarItem(title: "Home", url: home, symbol: "house", group: "Favorites"),
            SidebarItem(title: "Desktop", url: home.appendingPathComponent("Desktop", isDirectory: true), symbol: "menubar.rectangle", group: "Favorites"),
            SidebarItem(title: "Documents", url: home.appendingPathComponent("Documents", isDirectory: true), symbol: "doc", group: "Favorites"),
            SidebarItem(title: "Downloads", url: home.appendingPathComponent("Downloads", isDirectory: true), symbol: "arrow.down.circle", group: "Favorites"),
            SidebarItem(title: "Applications", url: URL(fileURLWithPath: "/Applications", isDirectory: true), symbol: "app", group: "Favorites"),
            SidebarItem(title: "Projects", url: home.appendingPathComponent("Projects", isDirectory: true), symbol: "hammer", group: "Favorites")
        ])
    }

    private func sandboxItems() -> [SidebarItem] {
        let root = ExperimentalFlags.appSandboxRoot
        return accessibleItems([
            SidebarItem(title: "Sandbox Root", url: root, symbol: "lock.square", group: "Workspace"),
            SidebarItem(title: "Left Pane", url: root.appendingPathComponent("Left Pane", isDirectory: true), symbol: "sidebar.left", group: "Workspace"),
            SidebarItem(title: "Right Pane", url: root.appendingPathComponent("Right Pane", isDirectory: true), symbol: "sidebar.right", group: "Workspace"),
            SidebarItem(title: "Projects", url: root.appendingPathComponent("Projects", isDirectory: true), symbol: "hammer", group: "Workspace"),
            SidebarItem(title: "Downloads", url: root.appendingPathComponent("Downloads", isDirectory: true), symbol: "arrow.down.circle", group: "Workspace")
        ])
    }

    private func deviceItems() -> [SidebarItem] {
        accessibleItems([
            SidebarItem(title: "Computer", url: URL(fileURLWithPath: "/", isDirectory: true), symbol: "desktopcomputer", group: "Devices & Locations"),
            SidebarItem(title: "Macintosh HD", url: URL(fileURLWithPath: "/", isDirectory: true), symbol: "internaldrive", group: "Devices & Locations")
        ])
    }

    private func recentItems() -> [SidebarItem] {
        accessibleItems(recentLocations.locations.map { url in
            SidebarItem(
                title: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                subtitle: displayPath(for: url),
                url: url,
                symbol: "clock",
                group: "Recent"
            )
        })
    }

    private func accessibleItems(_ items: [SidebarItem]) -> [SidebarItem] {
        items.filter { accessPolicy.canAccess($0.url) }
    }

    private func addSectionIfNeeded(_ title: String, items: [SidebarItem]) {
        guard !items.isEmpty else { return }
        if !stack.arrangedSubviews.isEmpty {
            addSpacer()
        }
        addSection(title)
        for item in items {
            addLocation(item)
        }
    }


    private func addSandboxRestrictionNote() {
        if !stack.arrangedSubviews.isEmpty {
            addSpacer()
        }

        let note = NSTextField(wrappingLabelWithString: ExperimentalFlags.sandboxRestrictionExplanation)
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = LiquidGlassStyle.secondaryLabel
        note.setContentCompressionResistancePriority(.required, for: .vertical)

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = LiquidGlassStyle.compactCornerRadius
        box.layer?.cornerCurve = .continuous
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(note)
        note.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            note.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            note.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            note.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8)
        ])

        stack.addArrangedSubview(box)
    }

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = LiquidGlassStyle.secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(5, after: label)
    }

    private func addLocation(_ item: SidebarItem) {
        let row = SidebarRowView(item: item)
        row.target = self
        row.action = #selector(openLocation(_:))
        row.identifier = NSUserInterfaceItemIdentifier(item.url.path)
        row.toolTip = item.url.path
        stack.addArrangedSubview(row)
    }

    private func addSpacer() {
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func displayPath(for url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    @objc private func openLocation(_ sender: NSControl) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpenLocation?(URL(fileURLWithPath: path), NSEvent.modifierFlags.contains(.option))
    }
}

private final class SidebarRowView: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateChrome() }
    }

    init(item: SidebarViewController.SidebarItem) {
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
        highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldOpen = bounds.contains(convert(event.locationInWindow, from: nil))
        highlight(false)
        if shouldOpen {
            sendAction(action, to: target)
        }
    }

    private func setup(item: SidebarViewController.SidebarItem) {
        wantsLayer = true
        layer?.cornerRadius = LiquidGlassStyle.compactCornerRadius
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: item.subtitle == nil ? 32 : 42).isActive = true

        imageView.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        imageView.contentTintColor = LiquidGlassStyle.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = LiquidGlassStyle.label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.stringValue = item.subtitle ?? ""
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = LiquidGlassStyle.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.isHidden = item.subtitle == nil
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.stringValue = item.badge.map(String.init) ?? ""
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = LiquidGlassStyle.secondaryLabel
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
        layer?.backgroundColor = (active ? LiquidGlassStyle.activeFill : hoverFill).cgColor
    }

    private func updateChrome() {
        layer?.backgroundColor = hoverFill.cgColor
        layer?.borderWidth = isHovering ? 1 : 0
        layer?.borderColor = LiquidGlassStyle.subtleStroke.cgColor
    }

    private var hoverFill: NSColor {
        isHovering ? NSColor(calibratedWhite: 1, alpha: 0.07) : .clear
    }
}

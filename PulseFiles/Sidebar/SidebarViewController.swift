import AppKit
import ImageIO

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

    struct InfoRow {
        let title: String
        let value: String
        let symbol: String
    }

    struct SelectionInspectorPresentation {
        let title: String
        let subtitle: String
        let icon: NSImage
        let rows: [InfoRow]
        let selectedURLs: [URL]

        static func make(for items: [FileItem]) -> SelectionInspectorPresentation? {
            guard !items.isEmpty else { return nil }
            if items.count == 1, let item = items.first {
                return SelectionInspectorPresentation(
                    title: item.displayName,
                    subtitle: displayPath(for: item.url),
                    icon: item.icon,
                    rows: singleSelectionRows(for: item),
                    selectedURLs: [item.url]
                )
            }

            let totalSize = items.reduce(Int64(0)) { $0 + $1.size }
            let folderCount = items.filter(\.isDirectory).count
            let fileCount = items.count - folderCount
            return SelectionInspectorPresentation(
                title: "\(items.count) items selected",
                subtitle: selectionBreakdown(fileCount: fileCount, folderCount: folderCount),
                icon: NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil) ?? NSImage(),
                rows: [
                    InfoRow(title: "Selected Items", value: "\(items.count)", symbol: "number"),
                    InfoRow(title: "Selected Size", value: FileSizeFormatter.string(fromByteCount: totalSize), symbol: "doc.on.doc"),
                    InfoRow(title: "Total Space", value: "Calculating…", symbol: "externaldrive"),
                    InfoRow(title: "Type", value: "Mixed selection", symbol: "tag")
                ],
                selectedURLs: items.map(\.url)
            )
        }

        private static func singleSelectionRows(for item: FileItem) -> [InfoRow] {
            var rows = [
                InfoRow(title: "Total Space", value: "Calculating…", symbol: "externaldrive"),
                InfoRow(title: "File Size", value: item.isDirectory ? "Folder" : FileSizeFormatter.string(fromByteCount: item.size), symbol: "doc.text"),
                InfoRow(title: "Type", value: item.fileType.displayName, symbol: item.isDirectory ? "folder" : "tag"),
                InfoRow(title: "Localized Type", value: item.localizedTypeDescription, symbol: "text.badge.checkmark")
            ]
            rows.append(InfoRow(title: "Created", value: formattedDate(item.creationDate), symbol: "calendar.badge.plus"))
            rows.append(InfoRow(title: "Modified", value: formattedDate(item.modificationDate), symbol: "calendar"))
            rows.append(InfoRow(title: "Permissions", value: formattedPermissions(item.posixPermissions), symbol: "lock.shield"))
            rows.append(InfoRow(title: "Owner", value: nonEmpty(item.owner), symbol: "person"))
            rows.append(InfoRow(title: "Group", value: nonEmpty(item.group), symbol: "person.2"))
            return rows
        }

        private static func selectionBreakdown(fileCount: Int, folderCount: Int) -> String {
            [pluralized(fileCount, singular: "file"), pluralized(folderCount, singular: "folder")]
                .filter { !$0.hasPrefix("0 ") }
                .joined(separator: ", ")
        }

        private static func pluralized(_ count: Int, singular: String) -> String {
            "\(count) \(singular)\(count == 1 ? "" : "s")"
        }

        private static func formattedDate(_ date: Date?) -> String {
            guard let date else { return "Unknown" }
            return dateFormatter.string(from: date)
        }

        private static func formattedPermissions(_ permissions: Int?) -> String {
            guard let permissions else { return "Unknown" }
            return String(format: "%03o", permissions & 0o777)
        }

        private static func nonEmpty(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return "Unknown" }
            return value
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        private static func displayPath(for url: URL) -> String {
            url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }

    private let recentLocations: RecentLocationService
    private let accessPolicy: SandboxFileAccessPolicy
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var selectedItems: [FileItem] = []
    private var sizeTask: Task<Void, Never>?
    private var representedSelectionID = UUID()

    init(recentLocations: RecentLocationService, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.recentLocations = recentLocations
        self.accessPolicy = accessPolicy
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit { sizeTask?.cancel() }

    override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = .hudWindow
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.panel)
        LiquidGlassStyle.applyPanelChrome(to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScrollView()
        configureStack()
        rebuild()
        recentLocations.onChange = { [weak self] _ in self?.rebuild() }
    }

    func refresh() { rebuild() }

    func showSelection(_ items: [FileItem]) {
        selectedItems = items
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
        stack.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.list)
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
        sizeTask?.cancel()
        representedSelectionID = UUID()
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        if selectedItems.isEmpty {
            addSectionIfNeeded("Recent", items: recentItems())
        } else {
            addFileInfo(for: selectedItems, selectionID: representedSelectionID)
        }
    }

    private func recentItems() -> [SidebarItem] {
        accessibleItems(recentLocations.locations.prefix(5).map { url in
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

    private func addFileInfo(for items: [FileItem], selectionID: UUID) {
        guard let presentation = SelectionInspectorPresentation.make(for: items) else { return }
        addHeader(title: presentation.title, subtitle: presentation.subtitle, icon: presentation.icon)
        addCopyPathButton(for: presentation.selectedURLs)
        addSection("Inspector")
        for row in presentation.rows {
            let identifier: String? = row.title == "Total Space" ? "total-size" : nil
            addInfoRow(row, identifier: identifier)
        }
        if items.count == 1, let item = items.first {
            if isImage(item) {
                addInfoRow(InfoRow(title: "GPS Location", value: "Reading metadata…", symbol: "location"), identifier: "gps-location")
            }
            loadDetails(for: item, selectionID: selectionID)
        } else {
            loadTotalSize(for: items, selectionID: selectionID)
        }
    }

    private func loadDetails(for item: FileItem, selectionID: UUID) {
        sizeTask = Task { [weak self] in
            let totalSize = await Self.totalSize(for: item.url, fallback: item.size)
            let gps = item.isDirectory ? nil : Self.gpsLocation(for: item.url)
            await MainActor.run {
                guard let self, self.representedSelectionID == selectionID else { return }
                self.updateInfoRow(identifier: "total-size", value: FileSizeFormatter.string(fromByteCount: totalSize))
                if self.isImage(item) {
                    self.updateInfoRow(identifier: "gps-location", value: gps ?? "No GPS metadata")
                }
            }
        }
    }

    private func loadTotalSize(for items: [FileItem], selectionID: UUID) {
        sizeTask = Task { [weak self] in
            var total: Int64 = 0
            for item in items where !Task.isCancelled {
                total += await Self.totalSize(for: item.url, fallback: item.size)
            }
            await MainActor.run {
                guard let self, self.representedSelectionID == selectionID else { return }
                self.updateInfoRow(identifier: "total-size", value: FileSizeFormatter.string(fromByteCount: total))
            }
        }
    }

    private static func totalSize(for url: URL, fallback: Int64) async -> Int64 {
        await Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return fallback }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return fallback }
            var total: Int64 = 0
            while let child = enumerator.nextObject() as? URL {
                if Task.isCancelled { return total }
                guard let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
                total += Int64(values.fileSize ?? 0)
            }
            return total
        }.value
    }

    private static func gpsLocation(for url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        let signedLat = latRef == "S" ? -latitude : latitude
        let signedLon = lonRef == "W" ? -longitude : longitude
        return String(format: "%.5f, %.5f", signedLat, signedLon)
    }

    private func isImage(_ item: FileItem) -> Bool {
        item.localizedTypeDescription.localizedCaseInsensitiveContains("image") || ["jpg", "jpeg", "png", "heic", "tiff", "gif"].contains(item.fileExtension.lowercased())
    }

    private func addSectionIfNeeded(_ title: String, items: [SidebarItem]) {
        guard !items.isEmpty else { return }
        addSection(title)
        for item in items { addLocation(item) }
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

    private func addHeader(title: String, subtitle: String, icon: NSImage) {
        let imageView = NSImageView(image: icon)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = LiquidGlassStyle.label
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = LiquidGlassStyle.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.spacing = 2
        let row = NSStackView(views: [imageView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32)
        ])
        stack.setCustomSpacing(14, after: row)
    }

    private func addInfoRow(_ info: InfoRow, identifier: String? = nil) {
        let row = SidebarInfoRowView(info: info)
        if let identifier { row.identifier = NSUserInterfaceItemIdentifier(identifier) }
        stack.addArrangedSubview(row)
    }

    private func addCopyPathButton(for urls: [URL]) {
        let button = NSButton(title: urls.count == 1 ? "Copy Path" : "Copy Paths", target: self, action: #selector(copySelectionPaths(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(urls.map(\.path).joined(separator: "\n"))
        button.toolTip = "Copy selected path information"
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        stack.addArrangedSubview(button)
        stack.setCustomSpacing(10, after: button)
    }

    private func updateInfoRow(identifier: String, value: String) {
        for view in stack.arrangedSubviews where view.identifier?.rawValue == identifier {
            (view as? SidebarInfoRowView)?.setValue(value)
        }
    }

    private func addLocation(_ item: SidebarItem) {
        let row = SidebarRowView(item: item)
        row.target = self
        row.action = #selector(openLocation(_:))
        row.identifier = NSUserInterfaceItemIdentifier(item.url.path)
        row.toolTip = item.url.path
        stack.addArrangedSubview(row)
    }

    private func displayPath(for url: URL) -> String { url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    @objc private func openLocation(_ sender: NSControl) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpenLocation?(URL(fileURLWithPath: path), NSEvent.modifierFlags.contains(.option))
    }

    @objc private func copySelectionPaths(_ sender: NSControl) {
        guard let paths = sender.identifier?.rawValue, !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }
}

private extension FileItemType {
    var displayName: String {
        switch self {
        case .folder: return "Folder"
        case .symbolicLink: return "Symbolic Link"
        case .package: return "Package"
        case .file: return "File"
        case .unknown: return "Unknown"
        }
    }
}

private final class SidebarInfoRowView: NSView {
    private let valueLabel = NSTextField(wrappingLabelWithString: "")

    init(info: SidebarViewController.InfoRow) {
        super.init(frame: .zero)
        setup(info: info)
    }

    required init?(coder: NSCoder) { nil }

    func setValue(_ value: String) { valueLabel.stringValue = value }

    private func setup(info: SidebarViewController.InfoRow) {
        wantsLayer = true
        layer?.cornerRadius = LiquidGlassStyle.compactCornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.04).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: NSImage(systemSymbolName: info.symbol, accessibilityDescription: info.title) ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        imageView.contentTintColor = LiquidGlassStyle.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: info.title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = LiquidGlassStyle.secondaryLabel

        valueLabel.stringValue = info.value
        valueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = LiquidGlassStyle.label
        valueLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView(views: [titleLabel, valueLabel])
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(textStack)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
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

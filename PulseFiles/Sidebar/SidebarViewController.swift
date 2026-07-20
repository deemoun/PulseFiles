import AppKit
import ImageIO

final class SidebarViewController: NSViewController {
    typealias MetadataReader = @Sendable (URL) throws -> String?

    var onOpenLocation: ((URL, Bool) -> Void)?

    /// Test-only observation point invoked after an inspector detail row has
    /// passed its selection and cancellation checks and is about to be updated.
    var onInspectorDetailUpdate: ((String, String) -> Void)?

    private enum SidebarMode: Int {
        case navigation
        case inspector

        var title: String {
            switch self {
            case .navigation: return "Navigation"
            case .inspector: return "Inspector"
            }
        }

        var symbolName: String {
            switch self {
            case .navigation: return "sidebar.left"
            case .inspector: return "info.circle"
            }
        }
    }

    struct SidebarItem {
        let title: String
        let subtitle: String?
        let url: URL
        let symbol: String
        let group: String
        let badge: Int?
        let isAvailable: Bool

        init(title: String, subtitle: String? = nil, url: URL, symbol: String, group: String, badge: Int? = nil, isAvailable: Bool = true) {
            self.title = title
            self.subtitle = subtitle
            self.url = url
            self.symbol = symbol
            self.group = group
            self.badge = badge
            self.isAvailable = isAvailable
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
                    icon: FileIconProvider.shared.image(for: item.iconKey),
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
    private let volumeDiscovery: any VolumeDiscovering
    private let metadataReader: MetadataReader
    private let scrollView = NSScrollView()
    private let modeControl = NSSegmentedControl()
    private let stack = NSStackView()
    private var selectedItems: [FileItem] = []
    private var selectedMode: SidebarMode = .navigation
    private var userSelectedMode = false
    private var sizeTask: Task<Void, Never>?
    private var deviceDiscoveryTask: Task<Void, Never>?
    private var deviceDiscoveryGeneration = 0
    private var lastSuccessfulDeviceVolumes: [Volume] = []
    private var representedSelectionID = UUID()

    init(
        recentLocations: RecentLocationService,
        accessPolicy: SandboxFileAccessPolicy = .current,
        volumeDiscovery: any VolumeDiscovering = VolumeDiscoveryService(),
        metadataReader: @escaping MetadataReader = SidebarViewController.gpsLocation
    ) {
        self.recentLocations = recentLocations
        self.accessPolicy = accessPolicy
        self.volumeDiscovery = volumeDiscovery
        self.metadataReader = metadataReader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        sizeTask?.cancel()
        deviceDiscoveryTask?.cancel()
    }

    override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.panel)
        LiquidGlassStyle.applyPanelChrome(to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureModeControl()
        configureScrollView()
        configureStack()
        rebuild()
        recentLocations.onChange = { [weak self] _ in self?.rebuild() }
    }

    func refresh() {
        (view as? NSVisualEffectView)?.material = LiquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        LiquidGlassStyle.applyPanelChrome(to: view)
        rebuild()
    }

    func showSelection(_ items: [FileItem]) {
        let hadNoSelection = selectedItems.isEmpty
        selectedItems = items
        if items.isEmpty {
            selectedMode = .navigation
            userSelectedMode = false
        } else if hadNoSelection && !userSelectedMode {
            selectedMode = .inspector
        }
        rebuild()
    }

    private func configureModeControl() {
        modeControl.segmentCount = SidebarMode.inspector.rawValue + 1
        for mode in [SidebarMode.navigation, .inspector] {
            modeControl.setLabel(mode.title, forSegment: mode.rawValue)
            modeControl.setImage(NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title), forSegment: mode.rawValue)
            modeControl.setWidth(94, forSegment: mode.rawValue)
        }
        modeControl.segmentStyle = .rounded
        modeControl.trackingMode = .selectOne
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            modeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            modeControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            modeControl.heightAnchor.constraint(equalToConstant: 30)
        ])
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
            scrollView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureStack() {
        stack.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.list)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func rebuild(refreshingDevices: Bool = true) {
        sizeTask?.cancel()
        representedSelectionID = UUID()
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        updateModeControl()

        switch selectedMode {
        case .navigation:
            addNavigationContent()
        case .inspector:
            addFileInfo(for: selectedItems, selectionID: representedSelectionID)
        }
        if refreshingDevices {
            refreshDeviceVolumesAsynchronously()
        }
    }

    private func updateModeControl() {
        if selectedItems.isEmpty {
            selectedMode = .navigation
        }
        modeControl.selectedSegment = selectedMode.rawValue
        modeControl.setEnabled(!selectedItems.isEmpty, forSegment: SidebarMode.inspector.rawValue)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let mode = SidebarMode(rawValue: sender.selectedSegment) else { return }
        guard mode != .inspector || !selectedItems.isEmpty else {
            selectedMode = .navigation
            updateModeControl()
            return
        }
        selectedMode = mode
        userSelectedMode = true
        rebuild()
    }

    private func addNavigationContent() {
        if ExperimentalFlags.restrictFileAccessToAppSandboxRoot {
            addSandboxBanner()
            addSectionIfNeeded("Workspace", items: sandboxItems())
        } else {
            addSectionIfNeeded("Favorites", items: favoriteItems())
            addSectionIfNeeded("Devices", items: deviceItems())
        }
        addSectionIfNeeded("Recent", items: recentItems())
        if stack.arrangedSubviews.isEmpty {
            addEmptyState("No accessible locations yet.")
        }
    }

    private func favoriteItems() -> [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return accessibleItems([
            SidebarItem(title: "Home", subtitle: displayPath(for: home), url: home, symbol: "house", group: "Favorites"),
            SidebarItem(title: "Desktop", subtitle: "~/Desktop", url: home.appendingPathComponent("Desktop", isDirectory: true), symbol: "desktopcomputer", group: "Favorites"),
            SidebarItem(title: "Documents", subtitle: "~/Documents", url: home.appendingPathComponent("Documents", isDirectory: true), symbol: "doc", group: "Favorites"),
            SidebarItem(title: "Downloads", subtitle: "~/Downloads", url: home.appendingPathComponent("Downloads", isDirectory: true), symbol: "arrow.down.circle", group: "Favorites"),
            SidebarItem(title: "Applications", subtitle: "/Applications", url: URL(fileURLWithPath: "/Applications", isDirectory: true), symbol: "app.badge", group: "Favorites")
        ])
    }

    private func sandboxItems() -> [SidebarItem] {
        let root = ExperimentalFlags.appSandboxRoot
        return accessibleItems([
            SidebarItem(title: "Sandbox Root", subtitle: displayPath(for: root), url: root, symbol: "lock.shield", group: "Workspace"),
            SidebarItem(title: "Left Pane", subtitle: displayPath(for: root.appendingPathComponent("Left Pane", isDirectory: true)), url: root.appendingPathComponent("Left Pane", isDirectory: true), symbol: "sidebar.left", group: "Workspace"),
            SidebarItem(title: "Right Pane", subtitle: displayPath(for: root.appendingPathComponent("Right Pane", isDirectory: true)), url: root.appendingPathComponent("Right Pane", isDirectory: true), symbol: "sidebar.right", group: "Workspace")
        ])
    }

    func deviceItems() -> [SidebarItem] {
        Self.deviceItems(volumes: lastSuccessfulDeviceVolumes, accessPolicy: accessPolicy)
    }

    /// Rebuilds navigation content after a mounted-volume change.
    func refreshDevices() {
        guard selectedMode == .navigation else { return }
        rebuild()
    }

    /// Keeps layout work independent from mounted-volume discovery, which can
    /// block on unavailable removable or network volumes.
    private func refreshDeviceVolumesAsynchronously() {
        deviceDiscoveryGeneration += 1
        let generation = deviceDiscoveryGeneration
        deviceDiscoveryTask?.cancel()
        let discovery = volumeDiscovery
        deviceDiscoveryTask = Task { [weak self] in
            let volumes = await discovery.mountedVolumes()
            guard !Task.isCancelled else { return }
            guard let self, self.deviceDiscoveryGeneration == generation else { return }
            self.lastSuccessfulDeviceVolumes = volumes
            guard self.selectedMode == .navigation else { return }
            self.rebuild(refreshingDevices: false)
        }
    }

    static func deviceItems(volumes: [Volume], accessPolicy: SandboxFileAccessPolicy) -> [SidebarItem] {
        VolumeDiscoveryService.sortedVolumes(volumes)
            .filter { !$0.displayName.isEmpty }
            .map { volume in
                let isAvailable = accessPolicy.canAccess(volume.url)
                return SidebarItem(
                    title: volume.displayName,
                    subtitle: volumeSubtitle(for: volume, isAvailable: isAvailable),
                    url: volume.url,
                    symbol: volumeSymbol(for: volume),
                    group: "Devices",
                    isAvailable: isAvailable
                )
            }
    }

    static func volumeSymbol(for volume: Volume) -> String {
        if volume.isNetwork { return "network" }
        if volume.isRemovable { return "externaldrive" }
        if volume.url.path == "/" { return "internaldrive" }
        return "opticaldiscdrive"
    }

    static func volumeSubtitle(for volume: Volume, isAvailable: Bool) -> String {
        var parts = [String]()
        if !isAvailable { parts.append("Permission required") }
        if let available = volume.availableCapacity, let total = volume.totalCapacity {
            parts.append("\(FileSizeFormatter.string(fromByteCount: available)) available of \(FileSizeFormatter.string(fromByteCount: total))")
        }
        if volume.isReadOnly { parts.append("Read-only") }
        return parts.isEmpty ? volume.url.path : parts.joined(separator: " • ")
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
        addInspectorSummary(presentation)
        let rows = visibleRows(presentation.rows)
        addInspectorRows("Overview", rows: rows.filter { Self.overviewRowTitles.contains($0.title) })
        addInspectorRows("Dates", rows: rows.filter { Self.dateRowTitles.contains($0.title) })
        addInspectorRows("Ownership", rows: rows.filter { Self.ownershipRowTitles.contains($0.title) })
        let knownTitles = Self.overviewRowTitles.union(Self.dateRowTitles).union(Self.ownershipRowTitles)
        let extraRows = rows.filter { !knownTitles.contains($0.title) }
        addInspectorRows("Details", rows: extraRows)
        if items.count == 1, let item = items.first, isImage(item) {
            addSection("Metadata")
            addInfoRow(InfoRow(title: "GPS Location", value: "Reading metadata…", symbol: "location"), identifier: "gps-location")
        }
        if items.count == 1, let item = items.first {
            loadDetails(for: item, selectionID: selectionID)
        } else {
            loadTotalSize(for: items, selectionID: selectionID)
        }
    }

    private static let overviewRowTitles: Set<String> = ["Selected Items", "Selected Size", "Total Space", "File Size", "Type", "Localized Type"]
    private static let dateRowTitles: Set<String> = ["Created", "Modified"]
    private static let ownershipRowTitles: Set<String> = ["Permissions", "Owner", "Group"]

    private func visibleRows(_ rows: [InfoRow]) -> [InfoRow] {
        rows.filter { !$0.value.isEmpty && $0.value != "Unknown" }
    }

    private func loadDetails(for item: FileItem, selectionID: UUID) {
        let accessPolicy = accessPolicy
        let metadataReader = metadataReader
        sizeTask = Task { [weak self] in
            let details = await Task.detached(priority: .utility) {
                let totalSize = Self.calculateTotalSize(for: item.url, fallback: item.size, accessPolicy: accessPolicy)
                let gps: String?
                if item.isDirectory {
                    gps = nil
                } else {
                    gps = (try? metadataReader(item.url)) ?? nil
                }
                return (totalSize, gps)
            }.value
            await MainActor.run {
                guard !Task.isCancelled, let self, self.representedSelectionID == selectionID else { return }
                let totalSize = FileSizeFormatter.string(fromByteCount: details.0)
                self.onInspectorDetailUpdate?("total-size", totalSize)
                self.updateInfoRow(identifier: "total-size", value: totalSize)
                if self.isImage(item) {
                    let gps = details.1 ?? "No GPS metadata"
                    self.onInspectorDetailUpdate?("gps-location", gps)
                    self.updateInfoRow(identifier: "gps-location", value: gps)
                }
            }
        }
    }

    private func loadTotalSize(for items: [FileItem], selectionID: UUID) {
        let accessPolicy = accessPolicy
        sizeTask = Task { [weak self] in
            var total: Int64 = 0
            for item in items where !Task.isCancelled {
                total += await Self.totalSize(for: item.url, fallback: item.size, accessPolicy: accessPolicy)
            }
            await MainActor.run {
                guard !Task.isCancelled, let self, self.representedSelectionID == selectionID else { return }
                let formattedTotal = FileSizeFormatter.string(fromByteCount: total)
                self.onInspectorDetailUpdate?("total-size", formattedTotal)
                self.updateInfoRow(identifier: "total-size", value: formattedTotal)
            }
        }
    }

    static func totalSize(for url: URL, fallback: Int64, accessPolicy: SandboxFileAccessPolicy = .current) async -> Int64 {
        await Task.detached(priority: .utility) {
            Self.calculateTotalSize(for: url, fallback: fallback, accessPolicy: accessPolicy)
        }.value
    }

    private static func calculateTotalSize(for url: URL, fallback: Int64, accessPolicy: SandboxFileAccessPolicy) -> Int64 {
        guard accessPolicy.canAccess(url, logDecision: false) else { return fallback }
        return accessPolicy.withAccess(to: [url]) {
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
        }
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
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        pinToSidebarContentWidth(label)
        stack.setCustomSpacing(6, after: label)
    }

    private func addSandboxBanner() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = LiquidGlassStyle.compactCornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.08).cgColor
        container.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.22).cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        imageView.contentTintColor = .systemYellow
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "Sandbox mode is on. File access is limited to the test workspace.")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = LiquidGlassStyle.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        container.addSubview(label)
        stack.addArrangedSubview(container)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            imageView.widthAnchor.constraint(equalToConstant: 17),
            imageView.heightAnchor.constraint(equalToConstant: 17),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        stack.setCustomSpacing(12, after: container)
    }

    private func addInspectorSummary(_ presentation: SelectionInspectorPresentation) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.035).cgColor
        container.layer?.borderColor = LiquidGlassStyle.subtleStroke.cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: presentation.icon)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: presentation.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = LiquidGlassStyle.label
        titleLabel.lineBreakMode = .byTruncatingTail

        let subtitleLabel = NSTextField(labelWithString: presentation.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = LiquidGlassStyle.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: presentation.selectedURLs.count == 1 ? "Copy Path" : "Copy Paths", target: self, action: #selector(copySelectionPaths(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(presentation.selectedURLs.map(\.path).joined(separator: "\n"))
        button.toolTip = "Copy selected path information".localized
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        container.addSubview(textStack)
        container.addSubview(button)
        stack.addArrangedSubview(container)
        pinToSidebarContentWidth(container)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 82),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            imageView.widthAnchor.constraint(equalToConstant: 38),
            imageView.heightAnchor.constraint(equalToConstant: 38),
            textStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 8),
            button.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10)
        ])
        stack.setCustomSpacing(14, after: container)
    }

    private func addInfoRow(_ info: InfoRow, identifier: String? = nil) {
        let row = SidebarInfoRowView(info: info)
        if let identifier { row.identifier = NSUserInterfaceItemIdentifier(identifier) }
        stack.addArrangedSubview(row)
        pinToSidebarContentWidth(row)
    }

    private func pinToSidebarContentWidth(_ view: NSView) {
        let widthConstraint = view.widthAnchor.constraint(
            equalTo: stack.widthAnchor,
            constant: -(stack.edgeInsets.left + stack.edgeInsets.right)
        )
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true
    }

    private func addInspectorRows(_ title: String, rows: [InfoRow]) {
        guard !rows.isEmpty else { return }
        addSection(title)
        for row in rows {
            let identifier: String? = row.title == "Total Space" ? "total-size" : nil
            addInfoRow(row, identifier: identifier)
        }
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(12, after: last)
        }
    }

    private func addCopyPathButton(for urls: [URL]) {
        let button = NSButton(title: urls.count == 1 ? "Copy Path" : "Copy Paths", target: self, action: #selector(copySelectionPaths(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(urls.map(\.path).joined(separator: "\n"))
        button.toolTip = "Copy selected path information".localized
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        stack.addArrangedSubview(container)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        stack.setCustomSpacing(12, after: container)
    }

    private func updateInfoRow(identifier: String, value: String) {
        for view in stack.arrangedSubviews where view.identifier?.rawValue == identifier {
            (view as? SidebarInfoRowView)?.setValue(value)
        }
    }

    private func addEmptyState(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = LiquidGlassStyle.secondaryLabel
        label.alignment = .center
        stack.addArrangedSubview(label)
    }

    private func addLocation(_ item: SidebarItem) {
        let row = SidebarRowView(item: item)
        row.isEnabled = item.isAvailable
        row.target = self
        row.action = #selector(openLocation(_:))
        row.identifier = NSUserInterfaceItemIdentifier(item.url.path)
        row.toolTip = item.url.path
        stack.addArrangedSubview(row)
    }

    private func displayPath(for url: URL) -> String { url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    @objc private func openLocation(_ sender: NSControl) {
        guard sender.isEnabled, let path = sender.identifier?.rawValue else { return }
        let url = URL(fileURLWithPath: path)
        guard accessPolicy.canAccess(url) else { return }
        onOpenLocation?(url, NSEvent.modifierFlags.contains(.option))
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
    private let valueLabel = NSTextField(labelWithString: "")

    init(info: SidebarViewController.InfoRow) {
        super.init(frame: .zero)
        setup(info: info)
    }

    required init?(coder: NSCoder) { nil }

    func setValue(_ value: String) {
        valueLabel.stringValue = value
        valueLabel.toolTip = value
    }

    private func setup(info: SidebarViewController.InfoRow) {
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: NSImage(systemSymbolName: info.symbol, accessibilityDescription: info.title) ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        imageView.contentTintColor = LiquidGlassStyle.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: info.title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = LiquidGlassStyle.secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.stringValue = info.value
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = LiquidGlassStyle.label
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

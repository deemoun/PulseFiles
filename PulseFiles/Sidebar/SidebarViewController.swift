import AppKit
import ImageIO

package protocol DirectorySizing: Sendable {
    func size(of root: URL) async throws -> DirectorySizeResult
}

extension DirectorySizingService: DirectorySizing {}

package final class SidebarViewController: NSViewController {
    typealias MetadataReader = @Sendable (URL) throws -> String?

    package var onOpenLocation: ((URL, Bool) -> Void)?

    /// Test-only observation point invoked after an inspector detail row has
    /// passed its selection and cancellation checks and is about to be updated.
    package var onInspectorDetailUpdate: ((String, String) -> Void)?

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


    private let recentLocations: any RecentLocationRecording
    private let bookmarkService: any BookmarkPersisting
    private let settings: SettingsService
    private let accessPolicy: SandboxFileAccessPolicy
    package var accessPolicyForCompositionTesting: SandboxFileAccessPolicy { accessPolicy }
    private let metadataReader: MetadataReader
    private let directorySizing: any DirectorySizing
    package var directorySizingForCompositionTesting: any DirectorySizing { directorySizing }
    private let scrollView = NSScrollView()
    private let documentView = SidebarDocumentView()
    private let modeControl = NSSegmentedControl()
    private let stack = NSStackView()
    private var selectedItems: [FileItem] = []
    private var selectedMode: SidebarMode = .navigation
    private var userSelectedMode = false
    private let inspectorModel = SelectionInspectorViewModel()
    private let navigationModel: SidebarNavigationModel
    private var representedSelectionID = 0
    private var liquidGlassStyle: LiquidGlassStyle

    package init(
        recentLocations: any RecentLocationRecording,
        bookmarkService: any BookmarkPersisting,
        settings: SettingsService,
        accessPolicy: SandboxFileAccessPolicy,
        volumeDiscovery: any VolumeDiscovering,
        directorySizing: any DirectorySizing,
        liquidGlassStyle: LiquidGlassStyle = LiquidGlassStyle(liquidGlassEnabled: false),
        metadataReader: @escaping MetadataReader = SidebarViewController.gpsLocation
    ) {
        self.recentLocations = recentLocations
        self.bookmarkService = bookmarkService
        self.settings = settings
        self.accessPolicy = accessPolicy
        self.navigationModel = SidebarNavigationModel(volumeDiscovery: volumeDiscovery)
        self.directorySizing = directorySizing
        self.metadataReader = metadataReader
        self.liquidGlassStyle = liquidGlassStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    package override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.panel)
        liquidGlassStyle.applyPanelChrome(to: view)
    }

    package override func viewDidLoad() {
        super.viewDidLoad()
        configureModeControl()
        configureScrollView()
        configureStack()
        rebuild()
        recentLocations.onChange = { [weak self] _ in self?.rebuild() }
    }

    package func refresh() {
        (view as? NSVisualEffectView)?.material = liquidGlassStyle.isEnabled ? .hudWindow : .contentBackground
        liquidGlassStyle.applyPanelChrome(to: view)
        rebuild()
    }

    package func refreshAppearance(style: LiquidGlassStyle) {
        liquidGlassStyle = style
        refresh()
    }

    package func showSelection(_ items: [FileItem]) {
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
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 14, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scrollView.documentView = documentView
        let documentMinimumHeight = documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        documentMinimumHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentMinimumHeight,

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        ])
    }

    private func rebuild(refreshingDevices: Bool = true) {
        representedSelectionID = inspectorModel.beginSelection()
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
        let isRestricted = ExperimentalFlags.restrictFileAccessToAppSandboxRoot
        if isRestricted { addSandboxBanner() }
        navigationModel.sections(
            scratch: scratchItems(), workspace: sandboxItems(), favorites: favoriteItems(),
            devices: deviceItems(), recent: recentItems(), isRestricted: isRestricted
        ).forEach { addSectionIfNeeded($0.title, items: $0.items) }
        if stack.arrangedSubviews.isEmpty {
            addEmptyState("No accessible locations yet.")
        }
    }

    package func scratchItems() -> [SidebarItem] {
        Self.scratchItems(directory: settings.scratchDirectory, accessPolicy: accessPolicy)
    }

    package static func scratchItems(directory: URL?, accessPolicy: SandboxFileAccessPolicy) -> [SidebarItem] {
        guard let directory, accessPolicy.canAccess(directory) else { return [] }
        return [SidebarItem(
            title: "Scratch Folder".localized,
            subtitle: directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            url: directory,
            symbol: "tray.full",
            group: "Temporary Workspace".localized
        )]
    }

    private func favoriteItems() -> [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saved = bookmarkService.load().map {
            SidebarItem(title: $0.title, subtitle: displayPath(for: $0.url), url: $0.url, symbol: "star", group: "Favorites", isAvailable: accessPolicy.canAccess($0.url))
        }
        return saved + accessibleItems([
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

    package func deviceItems() -> [SidebarItem] {
        Self.deviceItems(volumes: navigationModel.volumes, accessPolicy: accessPolicy)
    }

    /// Rebuilds navigation content after a mounted-volume change.
    package func refreshDevices() {
        guard selectedMode == .navigation else { return }
        rebuild()
    }

    /// Keeps layout work independent from mounted-volume discovery, which can
    /// block on unavailable removable or network volumes.
    private func refreshDeviceVolumesAsynchronously() {
        navigationModel.refresh { [weak self] in
            guard let self, self.selectedMode == .navigation else { return }
            self.rebuild(refreshingDevices: false)
        }
    }

    package static func deviceItems(volumes: [Volume], accessPolicy: SandboxFileAccessPolicy) -> [SidebarItem] {
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

    package static func volumeSymbol(for volume: Volume) -> String {
        if volume.isNetwork { return "network" }
        if volume.isRemovable { return "externaldrive" }
        if volume.url.path == "/" { return "internaldrive" }
        return "opticaldiscdrive"
    }

    package static func volumeSubtitle(for volume: Volume, isAvailable: Bool) -> String {
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

    private func addFileInfo(for items: [FileItem], selectionID: Int) {
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
            addSidebarInfoRow(SidebarInfoRow(title: "GPS Location", value: "Reading metadata…", symbol: "location"), identifier: "gps-location")
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

    private func visibleRows(_ rows: [SidebarInfoRow]) -> [SidebarInfoRow] {
        rows.filter { !$0.value.isEmpty && $0.value != "Unknown" }
    }

    private func loadDetails(for item: FileItem, selectionID: Int) {
        let directorySizing = directorySizing
        let metadataReader = metadataReader
        inspectorModel.run { [weak self] in
            let size = try? await directorySizing.size(of: item.url)
            let gps = item.isDirectory ? nil : await Task.detached(priority: .utility) {
                (try? metadataReader(item.url)) ?? nil
            }.value
            await MainActor.run {
                guard !Task.isCancelled, let self, self.inspectorModel.isCurrent(selectionID) else { return }
                let totalSize = Self.sizeDescription(size)
                self.onInspectorDetailUpdate?("total-size", totalSize)
                self.updateSidebarInfoRow(identifier: "total-size", value: totalSize)
                if self.isImage(item) {
                    let gps = gps ?? "No GPS metadata"
                    self.onInspectorDetailUpdate?("gps-location", gps)
                    self.updateSidebarInfoRow(identifier: "gps-location", value: gps)
                }
            }
        }
    }

    private func loadTotalSize(for items: [FileItem], selectionID: Int) {
        let directorySizing = directorySizing
        inspectorModel.run { [weak self] in
            var total: Int64 = 0
            var isPartial = false
            var hasValue = false
            for item in items where !Task.isCancelled {
                guard let result = try? await directorySizing.size(of: item.url) else {
                    isPartial = true
                    continue
                }
                hasValue = true
                total += result.bytes
                if case .partial = result.completeness { isPartial = true }
            }
            await MainActor.run {
                guard !Task.isCancelled, let self, self.inspectorModel.isCurrent(selectionID) else { return }
                let formattedTotal = hasValue
                    ? (isPartial ? "At least \(FileSizeFormatter.string(fromByteCount: total))" : FileSizeFormatter.string(fromByteCount: total))
                    : "Unavailable"
                self.onInspectorDetailUpdate?("total-size", formattedTotal)
                self.updateSidebarInfoRow(identifier: "total-size", value: formattedTotal)
            }
        }
    }

    nonisolated private static func sizeDescription(_ result: DirectorySizeResult?) -> String {
        guard let result else { return "Unavailable" }
        let value = FileSizeFormatter.string(fromByteCount: result.bytes)
        if case .partial = result.completeness { return "At least \(value)" }
        return value
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
        label.textColor = liquidGlassStyle.secondaryLabel
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
        label.textColor = liquidGlassStyle.secondaryLabel
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
        container.layer?.borderColor = liquidGlassStyle.subtleStroke.cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)

        let imageView = NSImageView(image: presentation.icon)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: presentation.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = liquidGlassStyle.label
        titleLabel.lineBreakMode = .byTruncatingTail

        let subtitleLabel = NSTextField(labelWithString: presentation.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = liquidGlassStyle.secondaryLabel
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
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        stack.setCustomSpacing(14, after: container)
    }

    private func addSidebarInfoRow(_ info: SidebarInfoRow, identifier: String? = nil) {
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

    private func addInspectorRows(_ title: String, rows: [SidebarInfoRow]) {
        guard !rows.isEmpty else { return }
        addSection(title)
        for row in rows {
            let identifier: String? = row.title == "Total Space" ? "total-size" : nil
            addSidebarInfoRow(row, identifier: identifier)
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

    private func updateSidebarInfoRow(identifier: String, value: String) {
        for view in stack.arrangedSubviews where view.identifier?.rawValue == identifier {
            (view as? SidebarInfoRowView)?.setValue(value)
        }
    }

    private func addEmptyState(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = liquidGlassStyle.secondaryLabel
        label.alignment = .center
        stack.addArrangedSubview(label)
    }

    private func addLocation(_ item: SidebarItem) {
        let row = SidebarRowView(item: item)
        row.isEnabled = item.isAvailable
        row.target = self
        row.action = #selector(openLocation(_:))
        row.identifier = NSUserInterfaceItemIdentifier(item.url.path)
        if item.group == "Temporary Workspace".localized {
            row.setAccessibilityIdentifier(AccessibilityIdentifiers.Sidebar.scratchFolder)
        }
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

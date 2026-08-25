import AppKit

@MainActor
package final class SettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case general, appearance, navigation, access, experimental
        var title: String {
            switch self { case .general: return "General".localized; case .appearance: return "Appearance".localized; case .navigation: return "Navigation".localized; case .access: return "Access".localized; case .experimental: return "Experimental".localized }
        }
        var symbolName: String {
            switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .navigation: return "folder"; case .access: return "lock.shield"; case .experimental: return "testtube.2" }
        }
    }

    package var onChange: (() -> Void)?
    package var onOpenScratchDirectory: ((URL) -> Void)? { didSet { navigationPage.onOpenScratchDirectory = onOpenScratchDirectory } }
    package var onMaintenanceCleanup: (() -> Void)? { didSet { generalPage.onMaintenanceCleanup = onMaintenanceCleanup } }
    package var onScratchCleanupResult: ((FileOperationResult, String) -> Void)? { didSet { navigationPage.onScratchCleanupResult = onScratchCleanupResult } }

    private let categoryControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private var selectedCategory: Category = .general
    private let generalPage: GeneralSettingsPageController
    private let navigationPage: NavigationSettingsPageController
    private let pages: [Category: SettingsPageController]

    package init(settings: SettingsService, stagingCleanupService: StagingCleanupService, scratchCleanupService: ScratchFolderCleanupService, accessPolicy: SandboxFileAccessPolicy, accessGrantService: FolderAccessGrantService, standardFolderAccess: any StandardFolderAccessProviding, folderSelection: any AuthorizedFolderSelecting) {
        let general = GeneralSettingsPageController(settings: settings, stagingCleanupService: stagingCleanupService)
        let appearance = AppearanceSettingsPageController(settings: settings)
        let navigation = NavigationSettingsPageController(settings: settings, accessPolicy: accessPolicy, scratchCleanupService: scratchCleanupService, folderSelection: folderSelection)
        let access = AccessSettingsPageController(accessPolicy: accessPolicy, accessGrantService: accessGrantService, standardAccess: standardFolderAccess, folderSelection: folderSelection)
        let experimental = ExperimentalSettingsPageController(settings: settings)
        self.generalPage = general; self.navigationPage = navigation
        self.pages = [.general: general, .appearance: appearance, .navigation: navigation, .access: access, .experimental: experimental]
        super.init(nibName: nil, bundle: nil)
        pages.values.forEach { page in page.onChange = { [weak self] in self?.onChange?() } }
        preferredContentSize = NSSize(width: 720, height: 520)
    }
    required init?(coder: NSCoder) { nil }
    package override func loadView() { view = NSView() }
    package override func viewDidLoad() { super.viewDidLoad(); buildLayout(); showSelectedPage() }

    package func reloadFromSettings() { pages.values.forEach { $0.reloadFromSettings() }; showSelectedPage() }

    private func buildLayout() {
        let title = NSTextField(labelWithString: "Settings".localized); title.font = .preferredFont(forTextStyle: .largeTitle)
        let subtitle = NSTextField(wrappingLabelWithString: "Configure PulseFiles defaults, navigation, access, appearance, and experimental features.".localized); subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 4; header.translatesAutoresizingMaskIntoConstraints = false
        categoryControl.segmentCount = Category.allCases.count; categoryControl.segmentStyle = .rounded; categoryControl.trackingMode = .selectOne; categoryControl.target = self; categoryControl.action = #selector(categoryChanged(_:)); categoryControl.translatesAutoresizingMaskIntoConstraints = false
        categoryControl.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.categoryControl)
        for category in Category.allCases { categoryControl.setLabel(category.title, forSegment: category.rawValue); categoryControl.setImage(NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.title), forSegment: category.rawValue); categoryControl.setWidth(124, forSegment: category.rawValue) }
        categoryControl.selectedSegment = selectedCategory.rawValue
        scrollView.drawsBackground = false; scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = false; scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.pageHost)
        let done = NSButton(title: "Done".localized, target: self, action: #selector(done(_:))); done.keyEquivalent = "\r"; done.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.done)
        let footer = NSStackView(views: [done]); footer.orientation = .horizontal; footer.distribution = .gravityAreas; footer.translatesAutoresizingMaskIntoConstraints = false
        [header, categoryControl, scrollView, footer].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), header.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            categoryControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), categoryControl.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18), categoryControl.heightAnchor.constraint(equalToConstant: 32),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), scrollView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 18), scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])
    }

    private func showSelectedPage() {
        guard isViewLoaded, let page = pages[selectedCategory] else { return }
        page.reloadFromSettings(); scrollView.documentView = page.rootView
        let minimumHeight = page.rootView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor); minimumHeight.priority = .defaultLow
        NSLayoutConstraint.activate([page.rootView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor), page.rootView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor), page.rootView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor), page.rootView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor), minimumHeight])
    }
    @objc private func categoryChanged(_ sender: NSSegmentedControl) { guard let category = Category(rawValue: sender.selectedSegment) else { return }; selectedCategory = category; showSelectedPage() }
    @objc private func done(_ sender: Any?) { closeSettings() }
    package override func keyDown(with event: NSEvent) { if event.keyCode == 53 { closeSettings() } else { super.keyDown(with: event) } }
    @objc override func cancelOperation(_ sender: Any?) { closeSettings() }
    private func closeSettings() { if let window = view.window { window.close() } else { dismiss(nil) } }

    package var appLanguageSelectorForTesting: NSPopUpButton { generalPage.languageSelectorForTesting }
    package var categoryControlForTesting: NSSegmentedControl { categoryControl }
    package var visiblePageForTesting: NSView? { scrollView.documentView }
    package func pageForTesting(_ category: Category) -> SettingsPageController? { pages[category] }
}

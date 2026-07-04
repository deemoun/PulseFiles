import AppKit

final class SidebarViewController: NSViewController {
    var onOpenLocation: ((URL, Bool) -> Void)?

    private let recentLocations: RecentLocationService
    private let accessPolicy: SandboxFileAccessPolicy
    private let stack = NSStackView()
    private var recentButtons: [NSButton] = []

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
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16)
        ])
        rebuild()
        recentLocations.onChange = { [weak self] _ in self?.rebuild() }
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        addSection("Shortcuts")
        if ExperimentalFlags.restrictFileAccessToAppSandboxRoot {
            addLocation("Sandbox Root", url: ExperimentalFlags.appSandboxRoot, symbol: "lock.square")
            addLocation("Left Pane", url: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true), symbol: "sidebar.left")
            addLocation("Right Pane", url: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true), symbol: "sidebar.right")
            addLocation("Projects", url: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Projects", isDirectory: true), symbol: "hammer")
            addLocation("Downloads", url: ExperimentalFlags.appSandboxRoot.appendingPathComponent("Downloads", isDirectory: true), symbol: "arrow.down.circle")
        } else {
            addLocation("Home", url: FileManager.default.homeDirectoryForCurrentUser, symbol: "house")
            addLocation("Projects", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects"), symbol: "hammer")
            addLocation("Downloads", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"), symbol: "arrow.down.circle")
            addLocation("Desktop", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"), symbol: "menubar.rectangle")
            addLocation("Documents", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"), symbol: "doc")
            addLocation("Applications", url: URL(fileURLWithPath: "/Applications"), symbol: "app")
        }
        addSpacer()
        addSection("Recent")
        for url in recentLocations.locations where accessPolicy.canAccess(url) {
            addLocation(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, url: url, symbol: "clock")
        }
    }

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = LiquidGlassStyle.secondaryLabel
        stack.addArrangedSubview(label)
    }

    private func addLocation(_ title: String, url: URL, symbol: String) {
        let subtitle = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let button = NSButton(title: "\(title)\n\(subtitle)", target: self, action: #selector(openLocation(_:)))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.alignment = .left
        LiquidGlassStyle.applyButtonChrome(to: button)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.identifier = NSUserInterfaceItemIdentifier(url.path)
        button.toolTip = url.path
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(button)
    }

    private func addSpacer() {
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
    }

    @objc private func openLocation(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpenLocation?(URL(fileURLWithPath: path), NSEvent.modifierFlags.contains(.option))
    }
}

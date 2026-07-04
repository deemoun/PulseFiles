import AppKit

final class TerminalViewController: NSViewController {
    private let terminalService = TerminalService()
    private let label = NSTextField(labelWithString: "")

    var suggestedWorkingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser {
        didSet { updateLabel() }
    }

    override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = .hudWindow
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tabs = NSSegmentedControl(labels: ["Terminal", "Output"], trackingMode: .selectOne, target: nil, action: nil)
        tabs.selectedSegment = 0
        tabs.translatesAutoresizingMaskIntoConstraints = false

        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabs)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabs.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 14)
        ])
        updateLabel()
    }

    private func updateLabel() {
        label.stringValue = "\(terminalService.shellPath) - \(suggestedWorkingDirectory.path)"
    }
}

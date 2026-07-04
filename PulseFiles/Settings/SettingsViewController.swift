import AppKit

final class SettingsViewController: NSViewController {
    var onChange: (() -> Void)?

    private let settings: SettingsService
    private let sidebarCheckbox = NSButton(checkboxWithTitle: "Show sidebar by default", target: nil, action: nil)
    private let terminalCheckbox = NSButton(checkboxWithTitle: "Show terminal by default", target: nil, action: nil)
    private let hiddenFilesCheckbox = NSButton(checkboxWithTitle: "Show hidden files by default", target: nil, action: nil)
    private let sidebarWidthSlider = NSSlider(value: 220, minValue: 180, maxValue: 300, target: nil, action: nil)
    private let sidebarWidthLabel = NSTextField(labelWithString: "220 pt")
    private let leftDirectoryField = NSTextField()
    private let rightDirectoryField = NSTextField()

    init(settings: SettingsService = SettingsService()) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 460, height: 330)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        loadSettings()
    }

    private func buildLayout() {
        let title = NSTextField(labelWithString: "Settings")
        title.font = .preferredFont(forTextStyle: .title2)

        [sidebarCheckbox, terminalCheckbox, hiddenFilesCheckbox].forEach {
            $0.target = self
            $0.action = #selector(controlChanged(_:))
        }

        sidebarWidthSlider.target = self
        sidebarWidthSlider.action = #selector(controlChanged(_:))
        sidebarWidthLabel.alignment = .right
        sidebarWidthLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        [leftDirectoryField, rightDirectoryField].forEach {
            $0.isEditable = false
            $0.isSelectable = true
            $0.lineBreakMode = .byTruncatingMiddle
        }

        let widthRow = NSStackView(views: [NSTextField(labelWithString: "Sidebar width"), sidebarWidthSlider, sidebarWidthLabel])
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 8

        let leftRow = directoryRow(title: "Left startup folder", field: leftDirectoryField, chooseAction: #selector(chooseLeftStartupDirectory(_:)), resetAction: #selector(resetLeftStartupDirectory(_:)))
        let rightRow = directoryRow(title: "Right startup folder", field: rightDirectoryField, chooseAction: #selector(chooseRightStartupDirectory(_:)), resetAction: #selector(resetRightStartupDirectory(_:)))

        let stack = NSStackView(views: [title, sidebarCheckbox, terminalCheckbox, hiddenFilesCheckbox, widthRow, separator(), leftRow, rightRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: preferredContentSize.height),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            widthRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sidebarWidthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            leftRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rightRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func directoryRow(title: String, field: NSTextField, chooseAction: Selector, resetAction: Selector) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 124).isActive = true
        let chooseButton = NSButton(title: "Choose…", target: self, action: chooseAction)
        let resetButton = NSButton(title: "Use Last", target: self, action: resetAction)
        let row = NSStackView(views: [label, field, chooseButton, resetButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func loadSettings() {
        sidebarCheckbox.state = settings.defaultSidebarVisible ? .on : .off
        terminalCheckbox.state = settings.defaultTerminalVisible ? .on : .off
        hiddenFilesCheckbox.state = settings.showHiddenFilesByDefault ? .on : .off
        sidebarWidthSlider.doubleValue = settings.preferredSidebarWidth
        updateSidebarWidthLabel()
        updateDirectoryFields()
    }

    private func updateSidebarWidthLabel() {
        sidebarWidthLabel.stringValue = "\(Int(settings.preferredSidebarWidth)) pt"
    }

    private func updateDirectoryFields() {
        leftDirectoryField.stringValue = settings.startupLeftDirectory?.path ?? "Last left folder (\(settings.lastLeftDirectory.path))"
        rightDirectoryField.stringValue = settings.startupRightDirectory?.path ?? "Last right folder (\(settings.lastRightDirectory.path))"
    }

    @objc private func controlChanged(_ sender: Any?) {
        settings.defaultSidebarVisible = sidebarCheckbox.state == .on
        settings.defaultTerminalVisible = terminalCheckbox.state == .on
        settings.showHiddenFilesByDefault = hiddenFilesCheckbox.state == .on
        settings.preferredSidebarWidth = sidebarWidthSlider.doubleValue
        updateSidebarWidthLabel()
        onChange?()
    }

    @objc private func chooseLeftStartupDirectory(_ sender: Any?) { chooseDirectory { [weak self] url in self?.settings.startupLeftDirectory = url; self?.updateDirectoryFields(); self?.onChange?() } }
    @objc private func chooseRightStartupDirectory(_ sender: Any?) { chooseDirectory { [weak self] url in self?.settings.startupRightDirectory = url; self?.updateDirectoryFields(); self?.onChange?() } }
    @objc private func resetLeftStartupDirectory(_ sender: Any?) { settings.startupLeftDirectory = nil; updateDirectoryFields(); onChange?() }
    @objc private func resetRightStartupDirectory(_ sender: Any?) { settings.startupRightDirectory = nil; updateDirectoryFields(); onChange?() }

    private func chooseDirectory(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let window = view.window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

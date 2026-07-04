import AppKit

final class TerminalViewController: NSViewController {
    private let terminalService = TerminalService()
    private let workingDirectoryLabel = NSTextField(labelWithString: "")
    private let commandField = NSTextField(string: "pwd")
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let outputView = NSTextView()
    private let scrollView = NSScrollView()

    private var runningProcess: Process?

    var suggestedWorkingDirectory: URL = ExperimentalFlags.appSandboxRoot {
        didSet { updateWorkingDirectoryLabel() }
    }

    override func loadView() {
        view = NSVisualEffectView()
        (view as? NSVisualEffectView)?.material = .hudWindow
        (view as? NSVisualEffectView)?.blendingMode = .withinWindow
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        updateWorkingDirectoryLabel()
        appendOutput("Ready. Commands run in the active pane folder.\n")
    }

    func focusCommandField() {
        view.window?.makeFirstResponder(commandField)
    }

    private func buildLayout() {
        let tabs = NSSegmentedControl(labels: ["Terminal", "Output"], trackingMode: .selectOne, target: nil, action: nil)
        tabs.selectedSegment = 0
        tabs.translatesAutoresizingMaskIntoConstraints = false

        workingDirectoryLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        workingDirectoryLabel.textColor = .secondaryLabelColor
        workingDirectoryLabel.lineBreakMode = .byTruncatingMiddle
        workingDirectoryLabel.translatesAutoresizingMaskIntoConstraints = false

        commandField.placeholderString = "Enter shell command"
        commandField.target = self
        commandField.action = #selector(runCommand)
        commandField.translatesAutoresizingMaskIntoConstraints = false

        runButton.target = self
        runButton.action = #selector(runCommand)
        runButton.bezelStyle = .rounded
        runButton.translatesAutoresizingMaskIntoConstraints = false

        stopButton.target = self
        stopButton.action = #selector(stopCommand)
        stopButton.bezelStyle = .rounded
        stopButton.isEnabled = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.textColor = .labelColor
        outputView.backgroundColor = .clear

        scrollView.documentView = outputView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabs)
        view.addSubview(workingDirectoryLabel)
        view.addSubview(commandField)
        view.addSubview(runButton)
        view.addSubview(stopButton)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabs.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            workingDirectoryLabel.leadingAnchor.constraint(equalTo: tabs.trailingAnchor, constant: 12),
            workingDirectoryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            workingDirectoryLabel.centerYAnchor.constraint(equalTo: tabs.centerYAnchor),

            commandField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            commandField.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            commandField.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),

            runButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -8),
            runButton.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 64),

            stopButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stopButton.centerYAnchor.constraint(equalTo: commandField.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 64),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: commandField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    private func updateWorkingDirectoryLabel() {
        guard isViewLoaded else { return }
        workingDirectoryLabel.stringValue = "\(terminalService.shellPath) - \(suggestedWorkingDirectory.path)"
    }

    @objc private func runCommand() {
        let command = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, runningProcess == nil else { return }

        appendOutput("\n$ \(command)\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = suggestedWorkingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        runningProcess = process
        runButton.isEnabled = false
        stopButton.isEnabled = true

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.appendOutput("\n[exit \(process.terminationStatus)]\n")
                self?.runningProcess = nil
                self?.runButton.isEnabled = true
                self?.stopButton.isEnabled = false
            }
        }

        do {
            try process.run()
        } catch {
            appendOutput("Could not run command: \(error.localizedDescription)\n")
            runningProcess = nil
            runButton.isEnabled = true
            stopButton.isEnabled = false
        }
    }

    @objc private func stopCommand() {
        runningProcess?.terminate()
    }

    private func appendOutput(_ text: String) {
        outputView.textStorage?.append(NSAttributedString(string: text))
        outputView.scrollRangeToVisible(NSRange(location: outputView.string.count, length: 0))
    }
}

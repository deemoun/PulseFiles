import AppKit

final class TerminalViewController: NSViewController {
    private let terminalService = TerminalService()
    private let terminalView = TerminalTextView()
    private let scrollView = NSScrollView()

    private var runningProcess: Process?
    private var promptStartIndex = 0
    var workingDirectoryProvider: (() -> URL)?

    var suggestedWorkingDirectory: URL = ExperimentalFlags.appSandboxRoot

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = LiquidGlassStyle.panelStroke.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        terminalView.onSubmit = { [weak self] command in
            self?.run(command)
        }
        appendLine("PulseFiles terminal")
        appendPrompt()
    }

    func focusCommandField() {
        view.window?.makeFirstResponder(terminalView)
    }

    private func buildLayout() {
        terminalView.isEditable = true
        terminalView.isSelectable = true
        terminalView.allowsUndo = false
        terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.textColor = .systemGreen
        terminalView.insertionPointColor = .systemGreen
        terminalView.backgroundColor = .black
        terminalView.drawsBackground = true
        terminalView.textContainerInset = NSSize(width: 12, height: 10)

        scrollView.documentView = terminalView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func run(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, runningProcess == nil else {
            appendPrompt()
            return
        }

        if let workingDirectoryProvider {
            suggestedWorkingDirectory = workingDirectoryProvider()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = suggestedWorkingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        runningProcess = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.append(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.runningProcess = nil
                if process.terminationStatus != 0 {
                    self?.appendLine("[exit \(process.terminationStatus)]")
                }
                self?.appendPrompt()
            }
        }

        do {
            try process.run()
        } catch {
            appendLine("Could not run command: \(error.localizedDescription)")
            runningProcess = nil
            appendPrompt()
        }
    }

    private func appendPrompt() {
        if let workingDirectoryProvider {
            suggestedWorkingDirectory = workingDirectoryProvider()
        }
        let folder = suggestedWorkingDirectory.lastPathComponent.isEmpty ? suggestedWorkingDirectory.path : suggestedWorkingDirectory.lastPathComponent
        append("\n\(terminalService.shellPath.components(separatedBy: "/").last ?? "zsh") \(folder) $ ")
        promptStartIndex = terminalView.string.count
        terminalView.currentPromptStart = promptStartIndex
    }

    private func appendLine(_ text: String) {
        append(text + "\n")
    }

    private func append(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemGreen,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ]
        terminalView.textStorage?.append(NSAttributedString(string: text, attributes: attributes))
        terminalView.currentPromptStart = promptStartIndex
        let end = terminalView.string.count
        terminalView.setSelectedRange(NSRange(location: end, length: 0))
        terminalView.scrollRangeToVisible(NSRange(location: end, length: 0))
    }
}

private final class TerminalTextView: NSTextView {
    var onSubmit: ((String) -> Void)?
    var currentPromptStart = 0

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            let command = currentCommand()
            insertNewline(nil)
            onSubmit?(command)
            return
        }
        if event.keyCode == 51, selectedRange().location <= currentPromptStart {
            return
        }
        super.keyDown(with: event)
    }

    private func currentCommand() -> String {
        let nsString = string as NSString
        guard currentPromptStart <= nsString.length else { return "" }
        return nsString.substring(from: currentPromptStart)
    }
}

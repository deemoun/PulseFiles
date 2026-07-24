import AppKit

final class TerminalViewController: NSViewController {
    /// These bounds keep a noisy command from making the text view grow without limit.
    static let maximumRetainedOutputBytes = 256 * 1024
    static let maximumRetainedOutputCharacters = 128 * 1024
    static let maximumRetainedOutputLines = 2_000

    private static let truncationNotice = "[Earlier terminal output truncated]\n"
    private let terminalService = TerminalService()
    private let terminalView = TerminalTextView()
    private let scrollView = NSScrollView()
    private let processFactory: () -> TerminalProcess
    private let accessPolicy: SandboxFileAccessPolicy

    private var runningProcess: TerminalProcess?
    private var runningOutputHandle: FileHandle?
    private var runningAccessScope: FolderAccessScope?
    private var promptStartIndex = 0
    private let outputLock = NSLock()
    private var pendingOutput = ""
    private var isOutputFlushScheduled = false
    var workingDirectoryProvider: (() -> URL)?
    var isShellInteractionAllowedProvider: (() -> Bool)?

    var suggestedWorkingDirectory: URL = ExperimentalFlags.appSandboxRoot

    init(
        processFactory: @escaping () -> TerminalProcess = { ProcessTerminalProcess() },
        accessPolicy: SandboxFileAccessPolicy = .current
    ) {
        self.processFactory = processFactory
        self.accessPolicy = accessPolicy
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopRunningCommand()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = LiquidGlassStyle.panelStroke.cgColor
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.panel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        terminalView.onSubmit = { [weak self] command in
            self?.run(command)
        }
        appendLine("PulseFiles Experimental Terminal")
        appendLine("Warning: shell commands can modify or delete files.")
        appendPrompt()
    }

    func refreshAppearance() {
        view.layer?.cornerRadius = LiquidGlassStyle.isEnabled ? LiquidGlassStyle.cornerRadius : LiquidGlassStyle.compactCornerRadius
        view.layer?.borderColor = LiquidGlassStyle.panelStroke.cgColor
    }

    func focusCommandField() {
        view.window?.makeFirstResponder(terminalView)
    }

    func stopRunningCommand() {
        guard runningProcess != nil || runningOutputHandle != nil else { return }
        let process = runningProcess
        runningOutputHandle?.readabilityHandler = nil
        runningOutputHandle = nil
        process?.terminationHandler = nil
        flushBufferedOutput()

        if process?.isRunning == true {
            process?.terminate()
            appendLine("[terminated]")
        }

        runningProcess = nil
        endRunningAccessScope()
    }

    /// Ends the current terminal session and removes all prior command output.
    ///
    /// The terminal panel is retained while hidden so that it can be shown again
    /// without rebuilding its view hierarchy. Resetting here prevents a hidden
    /// session, including a termination message, from appearing as an active
    /// session when the panel is reopened.
    func resetSession() {
        stopRunningCommand()
        discardBufferedOutput()
        terminalView.string = ""
        promptStartIndex = 0
        terminalView.currentPromptStart = 0
        appendPrompt()
    }

    func runCommandForTesting(_ command: String) {
        run(command)
    }

    var terminalTextForTesting: String {
        terminalView.string
    }

    var hasRunningAccessScopeForTesting: Bool {
        runningAccessScope != nil
    }

    func receiveOutputForTesting(_ text: String) {
        queueOutput(text)
    }

    func flushOutputForTesting() {
        flushBufferedOutput()
    }

    private func buildLayout() {
        terminalView.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.textView)
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
        guard !command.isEmpty else {
            DiagnosticLogger.log(.debug, category: "Terminal", "Ignored empty terminal command")
            appendPrompt()
            return
        }
        guard runningProcess == nil else {
            DiagnosticLogger.log(.warning, category: "Terminal", "Ignored terminal command because a process is already running")
            appendPrompt()
            return
        }
        guard isShellInteractionAllowedProvider?() ?? true else {
            DiagnosticLogger.log(.warning, category: "Terminal", "Blocked terminal command until the first-use warning is acknowledged")
            appendLine("Acknowledge the Experimental Terminal warning before running shell commands.")
            appendPrompt()
            return
        }

        if let workingDirectoryProvider {
            suggestedWorkingDirectory = workingDirectoryProvider()
        }

        do {
            try accessPolicy.validateAccess(to: suggestedWorkingDirectory)
        } catch {
            DiagnosticLogger.log(.warning, category: "Terminal", "Denied terminal launch because working directory is not accessible: path=\(DiagnosticLogger.sanitizedPath(suggestedWorkingDirectory)); reason=\(error.localizedDescription)")
            appendLine("Could not run command: working directory is not authorized.")
            if let failureReason = (error as? LocalizedError)?.failureReason {
                appendLine(failureReason)
            }
            appendPrompt()
            return
        }

        DiagnosticLogger.log(.info, category: "Terminal", "Starting terminal process: shell=\(terminalService.shellPath); workingDirectory=\(DiagnosticLogger.sanitizedPath(suggestedWorkingDirectory)); commandLength=\(command.count)")
        let accessScope = accessPolicy.beginAccess(to: [suggestedWorkingDirectory])
        let pipe = Pipe()
        let process = processFactory()
        process.configure(
            executableURL: URL(fileURLWithPath: terminalService.shellPath),
            arguments: ["-lc", command],
            environment: terminalService.defaultEnvironment,
            currentDirectoryURL: suggestedWorkingDirectory,
            outputPipe: pipe
        )
        runningProcess = process
        runningOutputHandle = pipe.fileHandleForReading
        runningAccessScope = accessScope

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queueOutput(text)
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remainingData = pipe.fileHandleForReading.availableData
            if !remainingData.isEmpty, let remainingText = String(data: remainingData, encoding: .utf8) {
                self?.queueOutput(remainingText)
            }
            DispatchQueue.main.async {
                guard self?.runningProcess === process else { return }
                DiagnosticLogger.log(process.terminationStatus == 0 ? .info : .warning, category: "Terminal", "Terminal process exited: status=\(process.terminationStatus); reason=\(process.terminationReason.rawValue)")
                self?.runningProcess = nil
                self?.runningOutputHandle = nil
                process.terminationHandler = nil
                self?.endRunningAccessScope()
                self?.flushBufferedOutput()
                if process.terminationStatus != 0 {
                    self?.appendLine("[exit \(process.terminationStatus)]")
                }
                self?.appendPrompt()
            }
        }

        do {
            try process.run()
        } catch {
            DiagnosticLogger.log(.error, category: "Terminal", "Failed to start terminal process: reason=\(error.localizedDescription)")
            appendLine("Could not run command: \(error.localizedDescription)")
            pipe.fileHandleForReading.readabilityHandler = nil
            runningOutputHandle = nil
            runningProcess = nil
            endRunningAccessScope()
            appendPrompt()
        }
    }

    private func endRunningAccessScope() {
        guard let runningAccessScope else { return }
        accessPolicy.endAccess(runningAccessScope)
        self.runningAccessScope = nil
    }

    /// Called from the file handle's background callback. Chunks are coalesced so at
    /// most one main-queue UI update is outstanding, which provides backpressure for
    /// high-volume terminal output without blocking the pipe reader.
    private func queueOutput(_ text: String) {
        outputLock.lock()
        pendingOutput.append(text)
        pendingOutput = boundedPendingOutput(pendingOutput)
        let shouldScheduleFlush = !isOutputFlushScheduled
        isOutputFlushScheduled = true
        outputLock.unlock()

        guard shouldScheduleFlush else { return }
        DispatchQueue.main.async { [weak self] in
            self?.flushBufferedOutput()
        }
    }

    /// Must run on the main thread.
    private func flushBufferedOutput() {
        outputLock.lock()
        let output = pendingOutput
        pendingOutput = ""
        isOutputFlushScheduled = false
        outputLock.unlock()

        guard !output.isEmpty else { return }
        append(output)
    }

    private func discardBufferedOutput() {
        outputLock.lock()
        pendingOutput = ""
        outputLock.unlock()
    }

    private func boundedPendingOutput(_ output: String) -> String {
        guard exceedsRetainedOutputLimit(output) else { return output }

        var retained = output
        while exceedsRetainedOutputLimit(retained), let newline = retained.firstIndex(of: "\n") {
            retained.removeSubrange(...newline)
        }
        if exceedsRetainedOutputLimit(retained) {
            retained = String(retained.suffix(max(0, Self.maximumRetainedOutputCharacters - Self.truncationNotice.count)))
            while retained.utf8.count + Self.truncationNotice.utf8.count > Self.maximumRetainedOutputBytes,
                  !retained.isEmpty {
                retained.removeFirst()
            }
        }

        while exceedsRetainedOutputLimit(Self.truncationNotice + retained), let newline = retained.firstIndex(of: "\n") {
            retained.removeSubrange(...newline)
        }
        return Self.truncationNotice + retained
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
        let retainedText = boundedTerminalText(afterAppending: text)
        terminalView.textStorage?.setAttributedString(NSAttributedString(string: retainedText, attributes: attributes))
        terminalView.currentPromptStart = promptStartIndex
        let end = terminalView.string.count
        terminalView.setSelectedRange(NSRange(location: end, length: 0))
        terminalView.scrollRangeToVisible(NSRange(location: end, length: 0))
    }

    private func boundedTerminalText(afterAppending text: String) -> String {
        var retained = terminalView.string + text
        var didTruncate = false

        while exceedsRetainedOutputLimit(retained), let newline = retained.firstIndex(of: "\n") {
            retained.removeSubrange(...newline)
            didTruncate = true
        }

        if exceedsRetainedOutputLimit(retained) {
            didTruncate = true
            let targetCharacterCount = max(0, Self.maximumRetainedOutputCharacters - Self.truncationNotice.count)
            if retained.count > targetCharacterCount {
                retained = String(retained.suffix(targetCharacterCount))
            }
            while retained.utf8.count + Self.truncationNotice.utf8.count > Self.maximumRetainedOutputBytes,
                  !retained.isEmpty {
                retained.removeFirst()
            }
        }

        if didTruncate {
            while exceedsRetainedOutputLimit(Self.truncationNotice + retained), let newline = retained.firstIndex(of: "\n") {
                retained.removeSubrange(...newline)
            }
            if exceedsRetainedOutputLimit(Self.truncationNotice + retained) {
                retained = String(retained.suffix(max(0, Self.maximumRetainedOutputCharacters - Self.truncationNotice.count)))
                while Self.truncationNotice.utf8.count + retained.utf8.count > Self.maximumRetainedOutputBytes,
                      !retained.isEmpty {
                    retained.removeFirst()
                }
            }
            retained = Self.truncationNotice + retained
        }

        promptStartIndex = min(promptStartIndex, retained.count)
        return retained
    }

    private func exceedsRetainedOutputLimit(_ text: String) -> Bool {
        text.utf8.count > Self.maximumRetainedOutputBytes
            || text.count > Self.maximumRetainedOutputCharacters
            || text.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            } > Self.maximumRetainedOutputLines
    }
}

protocol TerminalProcess: AnyObject {
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    var terminationReason: Process.TerminationReason { get }
    var terminationHandler: ((TerminalProcess) -> Void)? { get set }

    func configure(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        outputPipe: Pipe
    )
    func run() throws
    func terminate()
}

private final class ProcessTerminalProcess: TerminalProcess {
    private let process = Process()

    var isRunning: Bool {
        process.isRunning
    }

    var terminationStatus: Int32 {
        process.terminationStatus
    }

    var terminationReason: Process.TerminationReason {
        process.terminationReason
    }

    var terminationHandler: ((TerminalProcess) -> Void)? {
        didSet {
            guard terminationHandler != nil else {
                process.terminationHandler = nil
                return
            }
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.terminationHandler?(self)
            }
        }
    }

    func configure(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        outputPipe: Pipe
    ) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = outputPipe
    }

    func run() throws {
        try process.run()
    }

    func terminate() {
        process.terminate()
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

import AppKit
import Darwin

/// An opt-in terminal backed by one interactive shell, rather than a new shell
/// for every Return key press. The PTY is important: programs see a terminal,
/// so prompts, stderr, and interactive input behave as they do in Terminal.
final class TerminalViewController: NSViewController {
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
    private var runningAccessScope: FolderAccessScope?
    private let outputLock = NSLock()
    private var pendingOutput = ""
    private var isOutputFlushScheduled = false
    var workingDirectoryProvider: (() -> URL)?
    var isShellInteractionAllowedProvider: (() -> Bool)?
    var suggestedWorkingDirectory = ExperimentalFlags.appSandboxRoot

    init(processFactory: @escaping () -> TerminalProcess = { PTYTerminalProcess() }, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.processFactory = processFactory
        self.accessPolicy = accessPolicy
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { stopRunningCommand() }

    override func loadView() {
        view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor; view.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        view.layer?.cornerCurve = .continuous; view.layer?.masksToBounds = true; view.layer?.borderWidth = 1
        view.layer?.borderColor = LiquidGlassStyle.panelStroke.cgColor
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.panel)
    }
    override func viewDidLoad() {
        super.viewDidLoad(); buildLayout()
        terminalView.onInput = { [weak self] data in self?.sendInput(data) }
        appendLine("PulseFiles Beta Terminal".localized)
        appendLine("Warning: shell commands can modify or delete files.")
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let size = terminalView.bounds.size
        runningProcess?.resize(columns: max(1, Int(size.width / 7.8)), rows: max(1, Int(size.height / 16)))
    }
    func refreshAppearance() { view.layer?.cornerRadius = LiquidGlassStyle.isEnabled ? LiquidGlassStyle.cornerRadius : LiquidGlassStyle.compactCornerRadius; view.layer?.borderColor = LiquidGlassStyle.panelStroke.cgColor }
    func focusCommandField() { view.window?.makeFirstResponder(terminalView) }

    /// Stop is deliberately explicit: it terminates the shell and releases its
    /// security-scoped folder access. The next keystroke starts a fresh shell.
    func stopRunningCommand() {
        guard let process = runningProcess else { return }
        process.outputHandler = nil; process.terminationHandler = nil
        if process.isRunning { process.terminate(); appendLine("[terminated]") }
        runningProcess = nil; endRunningAccessScope(); flushBufferedOutput()
    }
    func resetSession() { stopRunningCommand(); discardBufferedOutput(); terminalView.string = ""; appendLine("[terminal reset]") }
    func runCommandForTesting(_ command: String) { sendInput(Data((command + "\n").utf8)) }
    var terminalTextForTesting: String { terminalView.string }
    var hasRunningAccessScopeForTesting: Bool { runningAccessScope != nil }
    func receiveOutputForTesting(_ text: String) { queueOutput(text) }
    func flushOutputForTesting() { flushBufferedOutput() }

    private func buildLayout() {
        terminalView.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.textView); terminalView.isEditable = false; terminalView.isSelectable = true
        terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular); terminalView.textColor = .systemGreen; terminalView.backgroundColor = .black; terminalView.drawsBackground = true; terminalView.textContainerInset = NSSize(width: 12, height: 10)
        scrollView.documentView = terminalView; scrollView.hasVerticalScroller = true; scrollView.borderType = .noBorder; scrollView.drawsBackground = false; scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView); NSLayoutConstraint.activate([scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor), scrollView.topAnchor.constraint(equalTo: view.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    private func sendInput(_ data: Data) {
        guard !data.isEmpty else { return }
        if runningProcess == nil { startSession() }
        runningProcess?.write(data)
    }
    private func startSession() {
        guard isShellInteractionAllowedProvider?() ?? true else { appendLine("Acknowledge the Beta Terminal warning before running shell commands.".localized); return }
        if let workingDirectoryProvider { suggestedWorkingDirectory = workingDirectoryProvider() }
        do { try accessPolicy.validateAccess(to: suggestedWorkingDirectory) } catch {
            appendLine("Could not start terminal: working directory is not authorized."); return
        }
        let process = processFactory(); let scope = accessPolicy.beginAccess(to: [suggestedWorkingDirectory])
        process.configure(executableURL: URL(fileURLWithPath: terminalService.shellPath), arguments: ["-i"], environment: terminalService.defaultEnvironment.merging(["TERM": "xterm-256color"], uniquingKeysWith: { _, new in new }), currentDirectoryURL: suggestedWorkingDirectory)
        process.outputHandler = { [weak self] data in self?.queueOutput(String(decoding: data, as: UTF8.self)) }
        process.terminationHandler = { [weak self, weak process] in DispatchQueue.main.async {
            guard let self, let process, self.runningProcess === process else { return }
            self.runningProcess = nil; self.endRunningAccessScope(); self.flushBufferedOutput(); self.appendLine(process.terminationStatus == 0 ? "[shell exited]" : "[exit \(process.terminationStatus)]")
        }}
        runningProcess = process; runningAccessScope = scope
        do { try process.run(); viewDidLayout() } catch { runningProcess = nil; endRunningAccessScope(); appendLine("Could not start terminal: \(error.localizedDescription)") }
    }
    private func endRunningAccessScope() { guard let scope = runningAccessScope else { return }; accessPolicy.endAccess(scope); runningAccessScope = nil }
    private func queueOutput(_ text: String) { outputLock.lock(); pendingOutput += text; pendingOutput = bounded(pendingOutput); let schedule = !isOutputFlushScheduled; isOutputFlushScheduled = true; outputLock.unlock(); if schedule { DispatchQueue.main.async { [weak self] in self?.flushBufferedOutput() } } }
    private func flushBufferedOutput() { outputLock.lock(); let output = pendingOutput; pendingOutput = ""; isOutputFlushScheduled = false; outputLock.unlock(); if !output.isEmpty { append(TerminalControlSequenceRenderer.render(output)) } }
    private func discardBufferedOutput() { outputLock.lock(); pendingOutput = ""; outputLock.unlock() }
    private func appendLine(_ text: String) { append(text + "\n") }
    private func append(_ text: String) { let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGreen, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]; terminalView.textStorage?.setAttributedString(NSAttributedString(string: bounded(terminalView.string + text), attributes: attributes)); let end = terminalView.string.count; terminalView.setSelectedRange(NSRange(location: end, length: 0)); terminalView.scrollRangeToVisible(NSRange(location: end, length: 0)) }
    private func bounded(_ text: String) -> String {
        func exceeds(_ value: String) -> Bool {
            value.utf8.count > Self.maximumRetainedOutputBytes
                || value.count > Self.maximumRetainedOutputCharacters
                || value.filter({ $0 == "\n" }).count > Self.maximumRetainedOutputLines
        }
        guard exceeds(text) else { return text }
        var value = text
        while exceeds(Self.truncationNotice + value), let newline = value.firstIndex(of: "\n") {
            value.removeSubrange(...newline)
        }
        while exceeds(Self.truncationNotice + value), !value.isEmpty { value.removeFirst() }
        return Self.truncationNotice + value
    }
}

protocol TerminalProcess: AnyObject {
    var isRunning: Bool { get }; var terminationStatus: Int32 { get }; var outputHandler: ((Data) -> Void)? { get set }; var terminationHandler: ((TerminalProcess) -> Void)? { get set }
    func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL)
    func run() throws; func write(_ data: Data); func resize(columns: Int, rows: Int); func terminate()
}

private final class PTYTerminalProcess: TerminalProcess {
    private let process = Process(); private var master: FileHandle?; private var masterFD: Int32 = -1
    var outputHandler: ((Data) -> Void)?; var terminationHandler: ((TerminalProcess) -> Void)?
    var isRunning: Bool { process.isRunning }; var terminationStatus: Int32 { process.terminationStatus }
    func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL) { process.executableURL = executableURL; process.arguments = arguments; process.environment = environment; process.currentDirectoryURL = currentDirectoryURL }
    func run() throws {
        var masterFD: Int32 = -1, slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        self.masterFD = masterFD; let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true); self.master = master
        process.standardInput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true); process.standardOutput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true); process.standardError = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        master.readabilityHandler = { [weak self] handle in let data = handle.availableData; if !data.isEmpty { self?.outputHandler?(data) } }
        process.terminationHandler = { [weak self] _ in guard let self else { return }; self.master?.readabilityHandler = nil; self.master = nil; self.masterFD = -1; self.terminationHandler?(self) }
        try process.run()
    }
    func write(_ data: Data) { try? master?.write(contentsOf: data) }
    func resize(columns: Int, rows: Int) { guard masterFD >= 0 else { return }; var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0); _ = ioctl(masterFD, TIOCSWINSZ, &size) }
    func terminate() { process.terminate() }
}

private enum TerminalControlSequenceRenderer {
    /// Preserve terminal line semantics while removing non-printing CSI/OSC
    /// controls. This keeps scrollback legible without pretending NSTextView is
    /// a full terminal emulator.
    static func render(_ text: String) -> String {
        var result = "", iterator = text.makeIterator()
        while let character = iterator.next() {
            if character == "\u{1B}", let next = iterator.next() { if next == "[" { while let item = iterator.next(), !(item >= "@" && item <= "~") {} } else if next == "]" { while let item = iterator.next(), item != "\u{7}" {} }; continue }
            if character == "\r" { continue }
            if character == "\u{8}" { if !result.isEmpty { result.removeLast() }; continue }
            if character.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x0A || $0.value == 0x09 }) { result.append(character) }
        }; return result
    }
}

private final class TerminalTextView: NSTextView {
    var onInput: ((Data) -> Void)?
    override func keyDown(with event: NSEvent) { if let characters = event.characters { onInput?(Data(characters.utf8)) } }
    override func insertText(_ string: Any, replacementRange: NSRange) { if let text = string as? String { onInput?(Data(text.utf8)) } }
}

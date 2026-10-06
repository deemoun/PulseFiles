// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftTerm
import PulseFilesPresentationSupport
import PulseFilesCapabilities
import PulseFilesUtilities

/// An opt-in terminal backed by one interactive shell, rather than a new shell
/// for every Return key press. The PTY is important: programs see a terminal,
/// so prompts, stderr, and interactive input behave as they do in Terminal.
package final class TerminalViewController: NSViewController {
    package static let maximumPendingOutputBytes = 256 * 1024
    private static let truncationNotice = "[Earlier terminal output truncated]\n"

    private let terminalService: any TerminalSessionProviding
    private let terminalView = TerminalTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 180), font: .monospacedSystemFont(ofSize: 13, weight: .regular))
    private let processFactory: () -> TerminalProcess
    private let accessPolicy: any OperationScopeAccessPolicy
    private var liquidGlassStyle: LiquidGlassStyle
    package var accessPolicyIdentityForCompositionTesting: ObjectIdentifier { ObjectIdentifier(accessPolicy) }
    private var runningProcess: TerminalProcess?
    private var runningAccessScope: FolderAccessScope?
    private let outputLock = NSLock()
    private var pendingOutput = Data()
    private var didDropOutput = false
    private var isOutputFlushScheduled = false
    package var workingDirectoryProvider: (() -> URL)?
    package var isShellInteractionAllowedProvider: (() -> Bool)?
    package var suggestedWorkingDirectory = ExperimentalFlags.appSandboxRoot

    package init(terminalService: any TerminalSessionProviding, processFactory: @escaping () -> TerminalProcess, accessPolicy: any OperationScopeAccessPolicy, liquidGlassStyle: LiquidGlassStyle = LiquidGlassStyle(liquidGlassEnabled: false)) {
        self.terminalService = terminalService
        self.processFactory = processFactory
        self.accessPolicy = accessPolicy
        self.liquidGlassStyle = liquidGlassStyle
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { stopRunningCommand() }

    package override func loadView() {
        view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor; view.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        view.layer?.cornerCurve = .continuous; view.layer?.masksToBounds = true; view.layer?.borderWidth = 1
        view.layer?.borderColor = liquidGlassStyle.panelStroke.cgColor
        view.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.panel)
    }
    package override func viewDidLoad() {
        super.viewDidLoad(); buildLayout()
        terminalView.onInput = { [weak self] data in self?.sendInput(data) }
        appendLine("PulseFiles Beta Terminal".localized)
        appendLine("Warning: shell commands can modify or delete files.")
    }
    package override func viewDidLayout() {
        super.viewDidLayout()
        let terminal = terminalView.getTerminal()
        runningProcess?.resize(columns: terminal.cols, rows: terminal.rows)
    }
    package func refreshAppearance(style: LiquidGlassStyle) { liquidGlassStyle = style; view.layer?.cornerRadius = liquidGlassStyle.isEnabled ? LiquidGlassStyle.cornerRadius : LiquidGlassStyle.compactCornerRadius; view.layer?.borderColor = liquidGlassStyle.panelStroke.cgColor }
    package func focusCommandField() {
        view.window?.makeFirstResponder(terminalView)
        startSessionIfAllowed()
    }

    /// Starts the persistent shell as soon as the panel becomes active, so the
    /// terminal presents a prompt instead of looking like a non-functional log.
    /// The experiment flag and first-use acknowledgement are still authoritative.
    package func startSessionIfAllowed() {
        guard runningProcess == nil, isShellInteractionAllowedProvider?() ?? false else { return }
        startSession()
    }

    /// Stop is deliberately explicit: it terminates the shell and releases its
    /// security-scoped folder access. The next keystroke starts a fresh shell.
    package func stopRunningCommand() {
        guard let process = runningProcess else { return }
        process.outputHandler = nil; process.terminationHandler = nil
        if process.isRunning { process.terminate(); appendLine("[terminated]") }
        runningProcess = nil; endRunningAccessScope(); flushBufferedOutput()
    }
    package func resetSession() { stopRunningCommand(); discardBufferedOutput(); terminalView.getTerminal().resetToInitialState(); appendLine("[terminal reset]") }
    package func runCommandForTesting(_ command: String) { sendInput(Data((command + "\n").utf8)) }
    package var terminalTextForTesting: String { String(decoding: terminalView.getTerminal().getBufferAsData(), as: UTF8.self) }
    package var hasRunningAccessScopeForTesting: Bool { runningAccessScope != nil }
    package func receiveOutputForTesting(_ text: String) { queueOutput(Data(text.utf8)) }
    package func receiveOutputDataForTesting(_ data: Data) { queueOutput(data) }
    package func flushOutputForTesting() { flushBufferedOutput() }
    package var pendingOutputByteCountForTesting: Int {
        outputLock.lock(); defer { outputLock.unlock() }; return pendingOutput.count
    }

    private func buildLayout() {
        terminalView.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.textView)
        terminalView.setAccessibilityLabel("Beta Terminal".localized)
        terminalView.terminalDelegate = terminalView
        terminalView.nativeForegroundColor = .textColor
        terminalView.nativeBackgroundColor = .textBackgroundColor
        terminalView.onResize = { [weak self] columns, rows in
            self?.runningProcess?.resize(columns: columns, rows: rows)
        }
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    private func sendInput(_ data: Data) {
        guard !data.isEmpty else { return }
        guard isShellInteractionAllowedProvider?() == true else {
            stopRunningCommand()
            appendLine("Acknowledge the Beta Terminal warning before running shell commands.".localized)
            return
        }
        if runningProcess == nil { startSession() }
        runningProcess?.write(data)
    }
    private func startSession() {
        guard isShellInteractionAllowedProvider?() ?? false else { appendLine("Acknowledge the Beta Terminal warning before running shell commands.".localized); return }
        if let workingDirectoryProvider { suggestedWorkingDirectory = workingDirectoryProvider() }
        do { try accessPolicy.validateAccess(to: suggestedWorkingDirectory) } catch {
            appendLine("Could not start terminal: working directory is not authorized."); return
        }
        let process = processFactory(); let scope = accessPolicy.beginAccess(to: [suggestedWorkingDirectory])
        process.configure(executableURL: URL(fileURLWithPath: terminalService.shellPath), arguments: ["-i"], environment: terminalService.defaultEnvironment.merging(["TERM": "xterm-256color"], uniquingKeysWith: { _, new in new }), currentDirectoryURL: suggestedWorkingDirectory)
        process.outputHandler = { [weak self] data in self?.queueOutput(data) }
        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.runningProcess === terminatedProcess else { return }
                self.runningProcess = nil; self.endRunningAccessScope(); self.flushBufferedOutput(); self.appendLine(terminatedProcess.terminationStatus == 0 ? "[shell exited]" : "[exit \(terminatedProcess.terminationStatus)]")
            }
        }
        runningProcess = process; runningAccessScope = scope
        let terminal = terminalView.getTerminal()
        process.resize(columns: terminal.cols, rows: terminal.rows)
        do { try process.run() } catch { runningProcess = nil; endRunningAccessScope(); appendLine("Could not start terminal: \(error.localizedDescription)") }
    }
    private func endRunningAccessScope() { guard let scope = runningAccessScope else { return }; accessPolicy.endAccess(scope); runningAccessScope = nil }
    private func queueOutput(_ data: Data) {
        outputLock.lock()
        pendingOutput.append(data)
        if pendingOutput.count > Self.maximumPendingOutputBytes {
            pendingOutput.removeFirst(pendingOutput.count - Self.maximumPendingOutputBytes)
            didDropOutput = true
        }
        let schedule = !isOutputFlushScheduled
        isOutputFlushScheduled = true
        outputLock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) { [weak self] in self?.flushBufferedOutput() }
        }
    }
    private func flushBufferedOutput() {
        outputLock.lock()
        let output = pendingOutput
        let dropped = didDropOutput
        pendingOutput = Data()
        didDropOutput = false
        isOutputFlushScheduled = false
        outputLock.unlock()
        if dropped { terminalView.getTerminal().resetToInitialState() }
        if !output.isEmpty { terminalView.feed(byteArray: Array(output)[...]) }
        if dropped { appendLine(Self.truncationNotice.trimmingCharacters(in: .newlines)) }
    }
    private func discardBufferedOutput() {
        outputLock.lock(); pendingOutput = Data(); didDropOutput = false; outputLock.unlock()
    }
    private func appendLine(_ text: String) {
        let prefix = terminalView.getTerminal().getCursorLocation().x == 0 ? "" : "\r\n"
        terminalView.feed(text: prefix + text + "\r\n")
    }
}

/// Native VT/xterm rendering and keyboard interpretation. Shell control sequences
/// update cursor cells instead of being stripped and appended to a text log.
package final class TerminalTextView: SwiftTerm.TerminalView, TerminalViewDelegate {
    package var onInput: ((Data) -> Void)?
    package var onResize: ((Int, Int) -> Void)?
    package func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) { onInput?(Data(data)) }
    package func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) { onResize?(newCols, newRows) }
    package func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    package func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    package func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    // Shell output cannot navigate/open arbitrary URLs or change the clipboard.
    package func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
    package func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
    package func bell(source: SwiftTerm.TerminalView) {}
    package func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

}

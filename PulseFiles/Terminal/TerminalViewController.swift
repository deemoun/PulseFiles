// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesPresentationSupport
import PulseFilesServices
import PulseFilesUtilities

/// An opt-in terminal backed by one interactive shell, rather than a new shell
/// for every Return key press. The PTY is important: programs see a terminal,
/// so prompts, stderr, and interactive input behave as they do in Terminal.
package final class TerminalViewController: NSViewController {
    package static let maximumRetainedOutputBytes = 256 * 1024
    package static let maximumRetainedOutputCharacters = 128 * 1024
    package static let maximumRetainedOutputLines = 2_000
    private static let truncationNotice = "[Earlier terminal output truncated]\n"

    private let terminalService: any TerminalSessionProviding
    private let terminalView = TerminalTextView()
    private let scrollView = NSScrollView()
    private let processFactory: () -> TerminalProcess
    private let accessPolicy: SandboxFileAccessPolicy
    private var liquidGlassStyle: LiquidGlassStyle
    package var accessPolicyForCompositionTesting: SandboxFileAccessPolicy { accessPolicy }
    private var runningProcess: TerminalProcess?
    private var runningAccessScope: FolderAccessScope?
    private let outputLock = NSLock()
    private var pendingOutput = ""
    private var isOutputFlushScheduled = false
    package var workingDirectoryProvider: (() -> URL)?
    package var isShellInteractionAllowedProvider: (() -> Bool)?
    package var suggestedWorkingDirectory = ExperimentalFlags.appSandboxRoot

    package init(terminalService: any TerminalSessionProviding, processFactory: @escaping () -> TerminalProcess, accessPolicy: SandboxFileAccessPolicy, liquidGlassStyle: LiquidGlassStyle = LiquidGlassStyle(liquidGlassEnabled: false)) {
        self.terminalService = terminalService
        self.processFactory = processFactory
        self.accessPolicy = accessPolicy
        self.liquidGlassStyle = liquidGlassStyle
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { stopRunningCommand() }

    override func loadView() {
        view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor; view.layer?.cornerRadius = LiquidGlassStyle.cornerRadius
        view.layer?.cornerCurve = .continuous; view.layer?.masksToBounds = true; view.layer?.borderWidth = 1
        view.layer?.borderColor = liquidGlassStyle.panelStroke.cgColor
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
    package func refreshAppearance(style: LiquidGlassStyle) { liquidGlassStyle = style; view.layer?.cornerRadius = liquidGlassStyle.isEnabled ? LiquidGlassStyle.cornerRadius : LiquidGlassStyle.compactCornerRadius; view.layer?.borderColor = liquidGlassStyle.panelStroke.cgColor }
    package func focusCommandField() {
        view.window?.makeFirstResponder(terminalView)
        startSessionIfAllowed()
    }

    /// Starts the persistent shell as soon as the panel becomes active, so the
    /// terminal presents a prompt instead of looking like a non-functional log.
    /// The experiment flag and first-use acknowledgement are still authoritative.
    package func startSessionIfAllowed() {
        guard runningProcess == nil, isShellInteractionAllowedProvider?() ?? true else { return }
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
    package func resetSession() { stopRunningCommand(); discardBufferedOutput(); terminalView.string = ""; appendLine("[terminal reset]") }
    package func runCommandForTesting(_ command: String) { sendInput(Data((command + "\n").utf8)) }
    package var terminalTextForTesting: String { terminalView.string }
    package var hasRunningAccessScopeForTesting: Bool { runningAccessScope != nil }
    package func receiveOutputForTesting(_ text: String) { queueOutput(text) }
    package func flushOutputForTesting() { flushBufferedOutput() }

    private func buildLayout() {
        terminalView.setAccessibilityIdentifier(AccessibilityIdentifiers.Terminal.textView); terminalView.isEditable = true; terminalView.isSelectable = true
        terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular); terminalView.textColor = .textColor; terminalView.insertionPointColor = .textColor; terminalView.backgroundColor = .textBackgroundColor; terminalView.drawsBackground = true; terminalView.textContainerInset = NSSize(width: 12, height: 10)
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
        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.runningProcess === terminatedProcess else { return }
                self.runningProcess = nil; self.endRunningAccessScope(); self.flushBufferedOutput(); self.appendLine(terminatedProcess.terminationStatus == 0 ? "[shell exited]" : "[exit \(terminatedProcess.terminationStatus)]")
            }
        }
        runningProcess = process; runningAccessScope = scope
        do { try process.run(); viewDidLayout() } catch { runningProcess = nil; endRunningAccessScope(); appendLine("Could not start terminal: \(error.localizedDescription)") }
    }
    private func endRunningAccessScope() { guard let scope = runningAccessScope else { return }; accessPolicy.endAccess(scope); runningAccessScope = nil }
    private func queueOutput(_ text: String) { outputLock.lock(); pendingOutput += text; pendingOutput = bounded(pendingOutput); let schedule = !isOutputFlushScheduled; isOutputFlushScheduled = true; outputLock.unlock(); if schedule { DispatchQueue.main.async { [weak self] in self?.flushBufferedOutput() } } }
    private func flushBufferedOutput() { outputLock.lock(); let output = pendingOutput; pendingOutput = ""; isOutputFlushScheduled = false; outputLock.unlock(); if !output.isEmpty { append(TerminalControlSequenceRenderer.render(output)) } }
    private func discardBufferedOutput() { outputLock.lock(); pendingOutput = ""; outputLock.unlock() }
    private func appendLine(_ text: String) { append(text + "\n") }
    private func append(_ text: String) { let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.textColor, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]; terminalView.textStorage?.setAttributedString(NSAttributedString(string: bounded(terminalView.string + text), attributes: attributes)); let end = terminalView.string.utf16.count; terminalView.setSelectedRange(NSRange(location: end, length: 0)); terminalView.scrollRangeToVisible(NSRange(location: end, length: 0)) }
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

package final class TerminalTextView: NSTextView {
    package var onInput: ((Data) -> Void)?
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": paste(nil)
            case "c", "a": super.keyDown(with: event)
            default: nextResponder?.keyDown(with: event)
            }
            return
        }
        guard let data = Self.inputData(keyCode: event.keyCode, characters: event.characters, modifiers: modifiers) else { return }
        onInput?(data)
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String { onInput?(Data(text.utf8)) }
    }
    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onInput?(Data(text.utf8))
    }
    override func cut(_ sender: Any?) {}
    override func deleteBackward(_ sender: Any?) { onInput?(Data([0x7f])) }

    package static func inputData(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags = []) -> Data? {
        let escapeSequences: [UInt16: String] = [
            123: "\u{1B}[D", 124: "\u{1B}[C", 125: "\u{1B}[B", 126: "\u{1B}[A",
            115: "\u{1B}[H", 119: "\u{1B}[F", 116: "\u{1B}[5~", 121: "\u{1B}[6~",
            117: "\u{1B}[3~"
        ]
        if let sequence = escapeSequences[keyCode] { return Data(sequence.utf8) }
        guard var characters, !characters.isEmpty else { return nil }
        if modifiers.contains(.option) { characters = "\u{1B}" + characters }
        return Data(characters.utf8)
    }
}

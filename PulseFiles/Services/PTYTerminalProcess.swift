// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import PulseFilesCapabilities

package final class PTYTerminalProcess: TerminalProcess {
    private static let workingDirectoryBootstrap =
        "directory=$1; shift; cd -P -- \"$directory\" || exit; exec \"$@\""

    private let process = Process()
    private var master: FileHandle?
    private var masterFD: Int32 = -1
    private var windowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    package var outputHandler: ((Data) -> Void)?
    package var terminationHandler: ((TerminalProcess) -> Void)?
    package var isRunning: Bool { process.isRunning }
    package var terminationStatus: Int32 { process.terminationStatus }

    package init() {}

    package func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL) {
        // On affected macOS versions, setting Process.currentDirectoryURL can
        // corrupt AppKit's subsequent view-layout state, even before run().
        // Change directory in the child instead. All user paths remain argv
        // values, never interpolated into shell source.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.workingDirectoryBootstrap, "pulsefiles-terminal",
            currentDirectoryURL.path, executableURL.path] + arguments
        process.environment = environment
    }

    package func run() throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var initialSize = windowSize
        guard openpty(&masterFD, &slaveFD, nil, nil, &initialSize) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Do not echo queued keystrokes before the interactive shell installs
        // its own line editor, which would otherwise echo the same input again.
        var attributes = termios()
        if tcgetattr(slaveFD, &attributes) == 0 {
            attributes.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(slaveFD, TCSANOW, &attributes)
        }
        self.masterFD = masterFD
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        self.master = master
        process.standardInput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        process.standardOutput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        process.standardError = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        master.readabilityHandler = { [weak self] handle in
            // Read only the currently available bytes. Foundation's counted
            // read can wait for a full buffer; availableData can raise an
            // Objective-C exception for the EIO returned at PTY EOF.
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                self?.outputHandler?(Data(bytes.prefix(count)))
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                handle.readabilityHandler = nil
            }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.master?.readabilityHandler = nil
            self.master = nil
            self.masterFD = -1
            self.terminationHandler?(self)
        }
        try process.run()
    }

    package func write(_ data: Data) { try? master?.write(contentsOf: data) }
    package func resize(columns: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        guard size.ws_col != windowSize.ws_col || size.ws_row != windowSize.ws_row else { return }
        windowSize = size
        guard masterFD >= 0 else { return }
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }
    package func terminate() { process.terminate() }
}

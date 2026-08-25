import Darwin
import Foundation

/// Narrow process capability used by the opt-in terminal presentation. All
/// writable descriptor construction stays behind this service boundary.
package protocol TerminalProcess: AnyObject {
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    var outputHandler: ((Data) -> Void)? { get set }
    var terminationHandler: ((TerminalProcess) -> Void)? { get set }
    func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL)
    func run() throws
    func write(_ data: Data)
    func resize(columns: Int, rows: Int)
    func terminate()
}

package final class PTYTerminalProcess: TerminalProcess {
    private let process = Process()
    private var master: FileHandle?
    private var masterFD: Int32 = -1
    package var outputHandler: ((Data) -> Void)?
    package var terminationHandler: ((TerminalProcess) -> Void)?
    package var isRunning: Bool { process.isRunning }
    package var terminationStatus: Int32 { process.terminationStatus }

    package init() {}

    package func configure(executableURL: URL, arguments: [String], environment: [String: String], currentDirectoryURL: URL) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
    }

    package func run() throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.masterFD = masterFD
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        self.master = master
        process.standardInput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        process.standardOutput = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        process.standardError = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        master.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.outputHandler?(data) }
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
        guard masterFD >= 0 else { return }
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }
    package func terminate() { process.terminate() }
}

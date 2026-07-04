import Foundation

final class TerminalService {
    var shellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}

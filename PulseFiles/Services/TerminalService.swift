import Foundation

final class TerminalService {
    var shellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var defaultEnvironment: [String: String] {
        sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
    }

    func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        var sanitizedEnvironment = environment

        if shouldReplaceTerminalType(sanitizedEnvironment["TERM"]) {
            sanitizedEnvironment["TERM"] = "xterm-256color"
        }

        if sanitizedEnvironment["LANG"]?.isEmpty ?? true {
            sanitizedEnvironment["LANG"] = "en_US.UTF-8"
        }

        if sanitizedEnvironment["LC_CTYPE"]?.isEmpty ?? true {
            sanitizedEnvironment["LC_CTYPE"] = sanitizedEnvironment["LANG"]
        }

        return sanitizedEnvironment
    }

    private func shouldReplaceTerminalType(_ terminalType: String?) -> Bool {
        guard let terminalType, !terminalType.isEmpty else { return true }
        return terminalType == "dumb"
    }
}

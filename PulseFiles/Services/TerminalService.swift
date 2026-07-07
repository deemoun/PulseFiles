import Foundation

final class TerminalService {
    var shellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var defaultEnvironment: [String: String] {
        sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
    }

    func defaultVisibilityState(settings: SettingsService) -> TerminalVisibilityState {
        DiagnosticLogger.log(.debug, category: "Terminal", "Resolved terminal visibility defaults: experimentEnabled=\(settings.experimentalTerminalEnabled); visibleByDefault=\(settings.defaultTerminalVisible)")
        return TerminalVisibilityState(
            isExperimentEnabled: settings.experimentalTerminalEnabled,
            isVisibleByDefault: settings.defaultTerminalVisible
        )
    }

    func warningState(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy = .current) -> TerminalWarningState {
        DiagnosticLogger.log(.info, category: "Terminal", "Resolved terminal warning state: acknowledged=\(settings.hasAcknowledgedTerminalWarning); sandboxRestrictionsEnabled=\(accessPolicy.isEnabled)")
        return TerminalWarningState(
            isAcknowledged: settings.hasAcknowledgedTerminalWarning,
            areSandboxRestrictionsEnabled: accessPolicy.isEnabled
        )
    }

    func acknowledgeFirstUseWarning(settings: SettingsService) {
        DiagnosticLogger.log(.info, category: "Terminal", "Terminal first-use warning acknowledged")
        settings.hasAcknowledgedTerminalWarning = true
    }

    func resolvedWorkingDirectory(activePaneURL: URL?, accessPolicy: SandboxFileAccessPolicy = .current) -> URL {
        guard let activePaneURL else {
            DiagnosticLogger.log(.debug, category: "Terminal", "Resolved working directory to sandbox root because active pane URL was unavailable")
            return accessPolicy.rootURL
        }
        let resolvedURL = accessPolicy.validatedDirectory(activePaneURL)
        DiagnosticLogger.log(.debug, category: "Terminal", "Resolved working directory: path=\(DiagnosticLogger.sanitizedPath(resolvedURL))")
        return resolvedURL
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

struct TerminalVisibilityState: Equatable {
    let isExperimentEnabled: Bool
    let isVisibleByDefault: Bool
}

struct TerminalWarningState: Equatable {
    let isAcknowledged: Bool
    let areSandboxRestrictionsEnabled: Bool

    var messageText: String {
        "Experimental terminal warning".localized
    }

    var informativeText: String {
        if areSandboxRestrictionsEnabled {
            return "The terminal runs shell commands in the selected folder. Commands can modify or delete files inside the PulseFiles experimental sandbox.".localized
        }

        return "The terminal runs shell commands in the selected folder. Commands can modify or delete files, including files outside PulseFiles because sandbox restrictions are disabled.".localized
    }
}

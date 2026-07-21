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
            areSandboxRestrictionsEnabled: accessPolicy.isEnabled,
            isDebugBuild: Self.isDebugBuild
        )
    }

    func acknowledgeFirstUseWarning(settings: SettingsService) {
        DiagnosticLogger.log(.info, category: "Terminal", "Terminal first-use warning acknowledged")
        settings.hasAcknowledgedTerminalWarning = true
    }

    func shouldAcknowledgeFirstUseWarning(response: Int, acknowledgementResponse: Int) -> Bool {
        response == acknowledgementResponse
    }

    func resolvedWorkingDirectory(activePaneURL: URL?, accessPolicy: SandboxFileAccessPolicy = .current) -> URL {
        guard let activePaneURL else {
            let fallbackDescription = accessPolicy.isEnabled ? "experimental sandbox root" : "default access-policy root"
            DiagnosticLogger.log(.debug, category: "Terminal", "Resolved working directory to \(fallbackDescription) because active pane URL was unavailable")
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

    private static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
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
    let isDebugBuild: Bool

    var messageText: String {
        "Post-V1 experimental terminal warning".localized
    }

    var informativeText: String {
        if isDebugBuild, areSandboxRestrictionsEnabled {
            return "The terminal runs shell commands in the selected folder. Commands can modify or delete files inside the PulseFiles experimental sandbox.".localized
        }

        return "The terminal runs shell commands in the selected folder. Commands can modify or delete files outside PulseFiles when sandbox restrictions are disabled, including folders macOS permits PulseFiles to access or folders you have granted with security-scoped access.".localized
    }
}

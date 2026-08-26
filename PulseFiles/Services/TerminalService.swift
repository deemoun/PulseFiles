// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package protocol TerminalSettingsProviding: AnyObject {
    var experimentalTerminalEnabled: Bool { get }
    var defaultTerminalVisible: Bool { get }
    var hasAcknowledgedTerminalWarning: Bool { get set }
}

package final class TerminalService {
    package init() {}

    package var shellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    package var defaultEnvironment: [String: String] {
        sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
    }

    package func defaultVisibilityState(settings: TerminalSettingsProviding) -> TerminalVisibilityState {
        DiagnosticLogger.log(.debug, category: "Terminal", "Resolved terminal visibility defaults: experimentEnabled=\(settings.experimentalTerminalEnabled); visibleByDefault=\(settings.defaultTerminalVisible)")
        return TerminalVisibilityState(
            isExperimentEnabled: settings.experimentalTerminalEnabled,
            isVisibleByDefault: settings.defaultTerminalVisible
        )
    }

    package func warningState(settings: TerminalSettingsProviding, accessPolicy: SandboxFileAccessPolicy = .current) -> TerminalWarningState {
        DiagnosticLogger.log(.info, category: "Terminal", "Resolved terminal warning state: acknowledged=\(settings.hasAcknowledgedTerminalWarning); sandboxRestrictionsEnabled=\(accessPolicy.isEnabled)")
        return TerminalWarningState(
            isAcknowledged: settings.hasAcknowledgedTerminalWarning,
            areSandboxRestrictionsEnabled: accessPolicy.isEnabled,
            isDebugBuild: Self.isDebugBuild
        )
    }

    package func acknowledgeFirstUseWarning(settings: TerminalSettingsProviding) {
        DiagnosticLogger.log(.info, category: "Terminal", "Terminal first-use warning acknowledged")
        settings.hasAcknowledgedTerminalWarning = true
    }

    package func shouldAcknowledgeFirstUseWarning(response: Int, acknowledgementResponse: Int) -> Bool {
        response == acknowledgementResponse
    }

    package func resolvedWorkingDirectory(activePaneURL: URL?, accessPolicy: SandboxFileAccessPolicy = .current) -> URL {
        guard let activePaneURL else {
            let fallbackDescription = accessPolicy.isEnabled ? "experimental sandbox root" : "default access-policy root"
            DiagnosticLogger.log(.debug, category: "Terminal", "Resolved working directory to \(fallbackDescription) because active pane URL was unavailable")
            return accessPolicy.rootURL
        }
        let resolvedURL = accessPolicy.validatedDirectory(activePaneURL)
        DiagnosticLogger.log(.debug, category: "Terminal", "Resolved working directory: path=\(DiagnosticLogger.sanitizedPath(resolvedURL))")
        return resolvedURL
    }

    package func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
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

package struct TerminalVisibilityState: Equatable {
    package let isExperimentEnabled: Bool
    package let isVisibleByDefault: Bool
}

package struct TerminalWarningState: Equatable {
    package let isAcknowledged: Bool
    package let areSandboxRestrictionsEnabled: Bool
    package let isDebugBuild: Bool

    package var messageText: String {
        "Beta Terminal warning".localized
    }

    package var informativeText: String {
        "Beta Terminal runs shell commands in the selected folder. Shell commands can modify or delete files and may access any locations macOS has authorized for PulseFiles.".localized
    }
}

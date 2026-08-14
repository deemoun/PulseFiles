import AppKit

/// Owns terminal policy and presentation state; split-view geometry stays in TerminalLayoutCoordinator.
@MainActor
final class TerminalPresentationCoordinator {
    enum ToggleResult: Equatable { case show, hide, disabled }
    private(set) var isVisible = false
    private let service: any TerminalStateProviding
    init(service: any TerminalStateProviding) { self.service = service }
    func toggle(isEnabled: Bool) -> ToggleResult {
        if isVisible { isVisible = false; return .hide }
        guard isEnabled else { return .disabled }
        isVisible = true; return .show
    }
    func synchronize(installed: Bool) { isVisible = installed }
    func workingDirectory(activePaneURL: URL, accessPolicy: SandboxFileAccessPolicy) -> URL? {
        service.resolvedWorkingDirectory(activePaneURL: activePaneURL, accessPolicy: accessPolicy)
    }
    func warningState(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy) -> TerminalWarningState {
        service.warningState(settings: settings, accessPolicy: accessPolicy)
    }
    func acknowledgeWarningIfNeeded(response: Int, acknowledgementResponse: Int, settings: SettingsService) {
        guard service.shouldAcknowledgeFirstUseWarning(response: response, acknowledgementResponse: acknowledgementResponse) else { return }
        service.acknowledgeFirstUseWarning(settings: settings)
    }
}

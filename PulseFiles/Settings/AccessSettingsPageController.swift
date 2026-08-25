import AppKit

@MainActor
package final class AccessSettingsPageController: SettingsPageControllerBase {
    private let accessPolicy: SandboxFileAccessPolicy
    private let grantService: FolderAccessGrantService
    private let standardAccess: any StandardFolderAccessProviding
    private let folderSelection: any AuthorizedFolderSelecting
    private var states: [StandardFolder: StandardFolderAccessState] = [:]

    package init(accessPolicy: SandboxFileAccessPolicy, accessGrantService: FolderAccessGrantService, standardAccess: any StandardFolderAccessProviding, folderSelection: any AuthorizedFolderSelecting) {
        self.accessPolicy = accessPolicy; self.grantService = accessGrantService
        self.standardAccess = standardAccess
        self.folderSelection = folderSelection
        super.init(); reloadFromSettings()
    }

    package override func reloadFromSettings() {
        install(sections: [section(title: "Effective Access Mode".localized, views: [statusView()]), section(title: "Folder Access Grants".localized, views: [grantsView()]), section(title: "Files & Folders Access".localized, views: [permissionsView()])])
    }

    private func statusView() -> NSView {
        let title = accessPolicy.isEnabled ? "DEBUG experimental sandbox is enabled".localized : "Normal macOS-governed file-manager access".localized
        let message = accessPolicy.isEnabled ? "File access is limited to the experimental sandbox root unless a folder has an explicit security-scoped grant. Sandbox root: %@".localized(with: accessPolicy.rootURL.path) : "PulseFiles uses the access that macOS allows for this app. Protected locations and folder grants are still checked through the file access policy.".localized
        let detail = NSTextField(wrappingLabelWithString: message); detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [NSTextField(labelWithString: title), detail]); stack.orientation = .vertical; stack.alignment = .leading
        return stack
    }

    private func grantsView() -> NSView {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        if grantService.grants.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString: "No persisted folder access grants.".localized)) }
        for grant in grantService.grants {
            let path = NSTextField(labelWithString: grant.url.path); path.lineBreakMode = .byTruncatingMiddle
            let revoke = FolderAccessGrantButton(title: "Revoke".localized, target: self, action: #selector(revoke(_:))); revoke.grantURL = grant.url
            let row = NSStackView(views: [path, revoke]); row.orientation = .horizontal; row.spacing = 8; rows.addArrangedSubview(row)
        }
        let grant = NSButton(title: "Grant Folder Access…".localized, target: self, action: #selector(grant(_:)))
        let refresh = NSButton(title: "Refresh Grant Status".localized, target: self, action: #selector(refresh(_:)))
        grant.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.grantFolderAccess)
        let controls = NSStackView(views: [grant, refresh]); controls.orientation = .horizontal
        let stack = NSStackView(views: [rows, controls]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        return stack
    }

    private func permissionsView() -> NSView {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 10
        for folder in StandardFolder.allCases {
            let message = NSTextField(wrappingLabelWithString: stateMessage(folder)); message.textColor = .secondaryLabelColor
            let text = NSStackView(views: [NSTextField(labelWithString: folder.title), message]); text.orientation = .vertical; text.alignment = .leading
            let button = NSButton(title: "Request Access".localized, target: self, action: #selector(request(_:))); button.identifier = .init(folder.rawValue)
            let row = NSStackView(views: [text, button]); row.orientation = .horizontal; row.alignment = .centerY; rows.addArrangedSubview(row)
        }
        let privacy = NSButton(title: "Open Privacy Settings".localized, target: self, action: #selector(openPrivacy(_:)))
        let stack = NSStackView(views: [rows, privacy]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        return stack
    }

    private func stateMessage(_ folder: StandardFolder) -> String {
        switch states[folder] { case .accessible: return "Accessible. PulseFiles completed a minimal folder read.".localized; case .deniedOrUnavailable: return "Denied or unavailable. Verify the folder exists and review access in System Settings if needed.".localized; case .requiresSystemSettingsReview: return "Requires review in System Settings. PulseFiles cannot change this privacy decision.".localized; case .blockedByExperimentalSandbox: return "Experimental sandbox mode blocks this folder unless it has a separate folder-access grant.".localized; case nil: return "Selecting Request Access asks macOS for access when needed.".localized }
    }
    @objc private func grant(_ sender: Any?) { let window = rootView.window; folderSelection.selectFolder(for: .init(prompt: "Grant Access".localized, message: "Choose a folder to grant PulseFiles access.".localized, acceptsExistingAccessibleURL: false, presentingWindow: window)) { [weak self] result in self?.grantService.refreshResolvedGrants(); self?.reloadFromSettings(); if case .failure(let failure) = result { folderSelection.presentFailure(failure, in: window) } } }
    @objc private func refresh(_ sender: Any?) { grantService.refreshResolvedGrants(); reloadFromSettings() }
    @objc private func revoke(_ sender: FolderAccessGrantButton) { guard let url = sender.grantURL else { return }; _ = grantService.removeGrant(for: url); reloadFromSettings() }
    @objc private func request(_ sender: NSButton) { guard let raw = sender.identifier?.rawValue, let folder = StandardFolder(rawValue: raw) else { return }; states[folder] = standardAccess.requestAccess(for: folder); reloadFromSettings() }
    @objc private func openPrivacy(_ sender: Any?) { guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }; NSWorkspace.shared.open(url) }
}

private final class FolderAccessGrantButton: NSButton { var grantURL: URL? }

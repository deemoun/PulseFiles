import AppKit

@MainActor
final class NavigationSettingsPageController: SettingsPageControllerBase {
    private let settings: SettingsService
    private let accessPolicy: SandboxFileAccessPolicy
    private let folderSelection: AuthorizedFolderSelectionCoordinator
    private let scratchCleanupService: ScratchFolderCleanupService
    private let leftField = NSTextField(), rightField = NSTextField(), scratchField = NSTextField()
    private let hiddenFiles = NSButton(checkboxWithTitle: "Show hidden files by default".localized, target: nil, action: nil)
    private let matchSelector = NSPopUpButton(), presentationSelector = NSPopUpButton()
    var onOpenScratchDirectory: ((URL) -> Void)?
    var onScratchCleanupResult: ((FileOperationResult, String) -> Void)?

    init(settings: SettingsService, accessPolicy: SandboxFileAccessPolicy, accessGrantService: FolderAccessGrantService, scratchCleanupService: ScratchFolderCleanupService) {
        self.settings = settings; self.accessPolicy = accessPolicy; self.scratchCleanupService = scratchCleanupService
        self.folderSelection = AuthorizedFolderSelectionCoordinator(accessPolicy: accessPolicy, grantService: accessGrantService)
        super.init()
        [leftField, rightField, scratchField].forEach { $0.isEditable = false; $0.isSelectable = true; $0.lineBreakMode = .byTruncatingMiddle }
        scratchField.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.scratchPath)
        hiddenFiles.target = self; hiddenFiles.action = #selector(browserChanged(_:)); hiddenFiles.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.hiddenFiles)
        matchSelector.addItems(withTitles: ["Fuzzy".localized, "Contains".localized, "Prefix".localized, "Suffix".localized, "Prefix or suffix".localized])
        presentationSelector.addItems(withTitles: ["Filter matching files".localized, "Show all files and highlight matches".localized])
        [matchSelector, presentationSelector].forEach { $0.target = self; $0.action = #selector(browserChanged(_:)) }
        matchSelector.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.quickSearchMatch)
        presentationSelector.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.quickSearchPresentation)
        install(sections: [
            section(title: "Startup Folders".localized, views: [directoryRow("Left startup folder".localized, field: leftField, choose: #selector(chooseLeft(_:)), reset: #selector(resetLeft(_:))), directoryRow("Right startup folder".localized, field: rightField, choose: #selector(chooseRight(_:)), reset: #selector(resetRight(_:)))]),
            section(title: "Temporary Workspace".localized, views: [scratchRow()]),
            section(title: "File Browser".localized, views: [hiddenFiles, labeledPopup("Quick search matching".localized, popup: matchSelector), labeledPopup("Quick search results".localized, popup: presentationSelector)])
        ])
        reloadFromSettings()
    }

    override func reloadFromSettings() {
        leftField.stringValue = settings.startupLeftDirectory?.path ?? "Last left folder (%@)".localized(with: settings.lastLeftDirectory.path)
        rightField.stringValue = settings.startupRightDirectory?.path ?? "Last right folder (%@)".localized(with: settings.lastRightDirectory.path)
        scratchField.stringValue = settings.scratchDirectory?.path ?? "No scratch folder configured".localized
        hiddenFiles.state = settings.showHiddenFilesByDefault ? .on : .off
        matchSelector.selectItem(at: QuickSearchMatchMode.allCases.firstIndex(of: settings.quickSearchMatchMode) ?? 0)
        presentationSelector.selectItem(at: QuickSearchPresentation.allCases.firstIndex(of: settings.quickSearchPresentation) ?? 0)
    }

    private func directoryRow(_ title: String, field: NSTextField, choose: Selector, reset: Selector) -> NSView {
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 124).isActive = true
        let row = NSStackView(views: [label, field, NSButton(title: "Choose…".localized, target: self, action: choose), NSButton(title: "Use Last".localized, target: self, action: reset)])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func scratchRow() -> NSView {
        let choose = NSButton(title: "Choose Folder…".localized, target: self, action: #selector(chooseScratch(_:)))
        let open = NSButton(title: "Open in Active Pane".localized, target: self, action: #selector(openScratch(_:)))
        let clean = NSButton(title: "Clean Up Contents…".localized, target: self, action: #selector(cleanScratch(_:)))
        let clear = NSButton(title: "Clear Setting".localized, target: self, action: #selector(clearScratch(_:)))
        choose.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.chooseScratchFolder); open.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.openScratchFolder); clear.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.clearScratchFolder)
        let controls = NSStackView(views: [choose, open, clean, clear]); controls.orientation = .horizontal; controls.spacing = 8
        let row = NSStackView(views: [scratchField, controls]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 8
        return row
    }

    @objc private func browserChanged(_ sender: Any?) {
        settings.showHiddenFilesByDefault = hiddenFiles.state == .on
        if QuickSearchMatchMode.allCases.indices.contains(matchSelector.indexOfSelectedItem) { settings.quickSearchMatchMode = QuickSearchMatchMode.allCases[matchSelector.indexOfSelectedItem] }
        if QuickSearchPresentation.allCases.indices.contains(presentationSelector.indexOfSelectedItem) { settings.quickSearchPresentation = QuickSearchPresentation.allCases[presentationSelector.indexOfSelectedItem] }
        onChange?()
    }
    @objc private func chooseLeft(_ sender: Any?) { choose { [weak self] in self?.settings.startupLeftDirectory = $0; self?.reloadFromSettings(); self?.onChange?() } }
    @objc private func chooseRight(_ sender: Any?) { choose { [weak self] in self?.settings.startupRightDirectory = $0; self?.reloadFromSettings(); self?.onChange?() } }
    @objc private func resetLeft(_ sender: Any?) { settings.startupLeftDirectory = nil; reloadFromSettings(); onChange?() }
    @objc private func resetRight(_ sender: Any?) { settings.startupRightDirectory = nil; reloadFromSettings(); onChange?() }
    @objc private func chooseScratch(_ sender: Any?) { choose { [weak self] url in guard let self else { return }; do { let value = try scratchCleanupService.captureSelection(for: url); settings.scratchDirectory = value.directory; settings.scratchFolderSelection = value; reloadFromSettings(); onChange?() } catch { NSAlert(error: error).runModal() } } }
    @objc private func openScratch(_ sender: Any?) { guard let url = settings.scratchDirectory, accessPolicy.canAccess(url) else { return }; onOpenScratchDirectory?(url) }
    @objc private func clearScratch(_ sender: Any?) { settings.scratchDirectory = nil; reloadFromSettings(); onChange?() }
    @objc private func cleanScratch(_ sender: Any?) {
        guard let selection = settings.scratchFolderSelection else { return }
        do {
            let inventory = try scratchCleanupService.inventory(for: selection)
            let alert = NSAlert(); alert.alertStyle = .critical; alert.messageText = "Clean Up Scratch Folder Contents?".localized
            alert.informativeText = ["Folder: %@".localized(with: inventory.selection.directory.path), "Items: %d".localized(with: inventory.itemCount), "Allocated size: %@".localized(with: FileSizeFormatter.string(fromByteCount: inventory.allocatedByteCount)), "Only the folder's contents will be affected. The configured folder itself will remain.".localized, "Move Contents to Trash is recoverable until the Trash is emptied. Permanently Delete cannot be undone.".localized].joined(separator: "\n")
            alert.addButton(withTitle: "Move Contents to Trash".localized); alert.addButton(withTitle: "Permanently Delete…".localized); alert.addButton(withTitle: "Cancel — Keep Contents".localized)
            let response = alert.runModal(); guard response != .alertThirdButtonReturn else { return }
            let action: ScratchFolderCleanupAction = response == .alertFirstButtonReturn ? .moveToTrash : .permanentlyDelete
            if action == .permanentlyDelete {
                let confirmation = NSAlert(); confirmation.alertStyle = .critical; confirmation.messageText = "Permanently Delete Scratch Folder Contents?".localized
                confirmation.informativeText = "This permanently deletes %d item(s) from %@ and cannot be undone. The folder itself will remain.".localized(with: inventory.itemCount, inventory.selection.directory.path)
                confirmation.addButton(withTitle: "Permanently Delete Contents".localized); confirmation.addButton(withTitle: "Cancel — Keep Contents".localized)
                guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            }
            Task { @MainActor [weak self] in guard let self else { return }; do { let result = try await scratchCleanupService.cleanup(inventory, action: action); onScratchCleanupResult?(result, action == .moveToTrash ? "Move to Trash".localized : "Permanently Delete".localized) } catch { NSAlert(error: error).runModal() } }
        } catch { NSAlert(error: error).runModal() }
    }
    private func choose(_ completion: @escaping (URL) -> Void) {
        let window = rootView.window
        folderSelection.selectFolder(for: .init(prompt: "Choose".localized, acceptsExistingAccessibleURL: true, presentingWindow: window)) { result in
            switch result { case .success(let url): completion(url); case .failure(let failure): FolderAccessFailurePresenter.present(failure, in: window) }
        }
    }
}

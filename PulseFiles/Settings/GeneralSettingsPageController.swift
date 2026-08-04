import AppKit

@MainActor
final class GeneralSettingsPageController: SettingsPageControllerBase {
    private let settings: SettingsService
    private let languageSelector = NSPopUpButton()
    private let confirmCopy = NSButton(checkboxWithTitle: "Confirm copy operations".localized, target: nil, action: nil)
    private let confirmMove = NSButton(checkboxWithTitle: "Confirm move operations".localized, target: nil, action: nil)
    private let confirmDelete = NSButton(checkboxWithTitle: "Confirm delete operations".localized, target: nil, action: nil)
    private let permanentDelete = NSButton(checkboxWithTitle: "Permanent delete instead of Move to Trash".localized, target: nil, action: nil)
    private let stagingCleanupService: StagingCleanupService
    private lazy var cleanupButton = NSButton(title: "Clear Incomplete Transfers…".localized, target: self, action: #selector(cleanup(_:)))
    var onMaintenanceCleanup: (() -> Void)?

    init(settings: SettingsService, stagingCleanupService: StagingCleanupService) {
        self.settings = settings
        self.stagingCleanupService = stagingCleanupService
        super.init()
        languageSelector.addItems(withTitles: AppLanguage.allCases.map(\.localizedDisplayName))
        languageSelector.target = self
        languageSelector.action = #selector(languageChanged(_:))
        languageSelector.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.languageSelector)
        [confirmCopy, confirmMove, confirmDelete, permanentDelete].forEach {
            $0.target = self; $0.action = #selector(optionChanged(_:))
        }
        confirmCopy.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.confirmCopy)
        confirmMove.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.confirmMove)
        confirmDelete.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.confirmDelete)
        permanentDelete.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.permanentDelete)
        cleanupButton.setAccessibilityIdentifier(AccessibilityIdentifiers.Settings.clearIncompleteTransfers)
        install(sections: [
            section(title: "Language".localized, views: [languageRow()]),
            section(title: "File Operations".localized, views: [confirmCopy, confirmMove, confirmDelete, permanentDelete]),
            section(title: "Storage & Maintenance".localized, views: [cleanupButton])
        ])
        reloadFromSettings()
    }

    override func reloadFromSettings() {
        languageSelector.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.appLanguage) ?? 0)
        confirmCopy.state = settings.confirmCopyOperations ? .on : .off
        confirmMove.state = settings.confirmMoveOperations ? .on : .off
        confirmDelete.state = settings.confirmDeleteOperations ? .on : .off
        permanentDelete.state = settings.permanentlyDeleteInsteadOfTrash ? .on : .off
    }

    private func languageRow() -> NSView {
        let note = NSTextField(wrappingLabelWithString: "Language changes apply after restarting PulseFiles.".localized)
        note.textColor = .secondaryLabelColor
        let text = NSStackView(views: [NSTextField(labelWithString: "App language".localized), note])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        let row = NSStackView(views: [text, languageSelector])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        return row
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.appLanguage = AppLanguage.allCases[sender.indexOfSelectedItem]
        onChange?()
    }

    @objc private func optionChanged(_ sender: Any?) {
        settings.confirmCopyOperations = confirmCopy.state == .on
        settings.confirmMoveOperations = confirmMove.state == .on
        settings.confirmDeleteOperations = confirmDelete.state == .on
        settings.permanentlyDeleteInsteadOfTrash = permanentDelete.state == .on
        onChange?()
    }

    @objc private func cleanup(_ sender: Any?) {
        cleanupButton.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let inventory = await Task.detached(priority: .utility) { self.stagingCleanupService.inventory() }.value
            let alert = NSAlert()
            alert.messageText = "Clear Incomplete Transfers?".localized
            alert.informativeText = "%@ safely identifiable abandoned item(s), using %@.".localized(with: inventory.candidates.count, FileSizeFormatter.string(fromByteCount: inventory.totalByteCount))
            alert.addButton(withTitle: "Clear Identified Items".localized)
            alert.addButton(withTitle: "Cancel".localized)
            guard alert.runModal() == .alertFirstButtonReturn else { cleanupButton.isEnabled = true; return }
            let result = await stagingCleanupService.cleanup(inventory.candidates)
            cleanupButton.isEnabled = true
            onMaintenanceCleanup?()
            let report = NSAlert()
            report.messageText = result.failures.isEmpty ? "Incomplete transfers cleared".localized : "Some incomplete transfers could not be cleared".localized
            report.informativeText = result.failures.isEmpty ? "%@ item(s) removed.".localized(with: result.removed.count) : result.failures.map { "\($0.url.path): \($0.message)" }.joined(separator: "\n")
            report.runModal()
        }
    }

    var languageSelectorForTesting: NSPopUpButton { languageSelector }
}

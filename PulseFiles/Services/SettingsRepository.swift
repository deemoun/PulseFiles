import Foundation
import PulseFilesModels
import PulseFilesUtilities

package protocol SettingsPersisting: AnyObject {
    var snapshot: SettingsSnapshot { get }
    func update(_ mutation: (inout SettingsSnapshot) -> Void)
    func importJSONIfChanged()
    @discardableResult func writeSettingsJSON() throws -> URL
}

/// Owns the v1 UserDefaults and JSON persistence contract. JSON replacement is
/// atomic and a malformed or unsupported document never replaces known-good defaults.
package final class SettingsRepository: SettingsPersisting {
    package static let schemaVersion = 1
    package static let appLanguageDefaultsKey = "appLanguage"
    package static let lastImportDefaultsKey = "settingsJSONLastImportedModificationTime"

    private let defaults: UserDefaults
    private let syncsJSON: Bool
    private let jsonURLProvider: () -> URL
    private var isSynchronizing = false

    package init(defaults: UserDefaults = .standard, jsonURLProvider: (() -> URL)? = nil) {
        self.defaults = defaults
        syncsJSON = defaults === UserDefaults.standard || jsonURLProvider != nil
        self.jsonURLProvider = jsonURLProvider ?? { Self.defaultJSONURL }
        if syncsJSON {
            importJSONIfChanged()
            try? writeSettingsJSON()
        }
    }

    package static var defaultJSONURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("PulseFiles/Settings.json")
    }

    package var snapshot: SettingsSnapshot { readSnapshot() }

    package func update(_ mutation: (inout SettingsSnapshot) -> Void) {
        var value = readSnapshot()
        mutation(&value)
        writeSnapshot(value)
        writeIfNeeded()
    }

    package func importJSONIfChanged() {
        guard syncsJSON else { return }
        let url = jsonURLProvider()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              modified.timeIntervalSince1970 > (defaults.object(forKey: Self.lastImportDefaultsKey) as? Double ?? 0),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version <= Self.schemaVersion else { return }
        isSynchronizing = true
        writeSnapshot(migrated(document.settings, over: readSnapshot()))
        defaults.set(modified.timeIntervalSince1970, forKey: Self.lastImportDefaultsKey)
        isSynchronizing = false
        writeIfNeeded()
    }

    @discardableResult package func writeSettingsJSON() throws -> URL {
        let url = jsonURLProvider()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var exported = readSnapshot()
#if !DEBUG
        exported.experimentalSandboxEnabled = nil
#endif
        try encoder.encode(Document(version: Self.schemaVersion, settings: exported)).write(to: url, options: .atomic)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let modified = attributes[.modificationDate] as? Date {
            defaults.set(modified.timeIntervalSince1970, forKey: Self.lastImportDefaultsKey)
        }
        return url
    }

    private func writeIfNeeded() { if syncsJSON && !isSynchronizing { try? writeSettingsJSON() } }

    private func readSnapshot() -> SettingsSnapshot {
        var s = SettingsSnapshot()
        s.appLanguage = defaults.string(forKey: Self.appLanguageDefaultsKey)
        s.defaultSidebarVisible = bool("defaultSidebarVisible") ?? bool("isSidebarVisible")
        s.liquidGlassEnabled = bool("liquidGlassEnabled")
        s.experimentalTerminalEnabled = bool("experimentalTerminalEnabled")
        s.hasAcknowledgedTerminalWarning = bool("hasAcknowledgedTerminalWarning")
        s.defaultTerminalVisible = bool("defaultTerminalVisible")
        s.defaultSinglePaneMode = bool("defaultSinglePaneMode")
        s.showHiddenFilesByDefault = bool("showHiddenFilesByDefault")
        s.defaultPanePresentationMode = enumValue("defaultPanePresentationMode")
        s.leftPanePresentationMode = enumValue("leftPanePresentationMode")
        s.rightPanePresentationMode = enumValue("rightPanePresentationMode")
        s.quickSearchMatchMode = enumValue("quickSearchMatchMode")
        s.quickSearchPresentation = enumValue("quickSearchPresentation")
        s.confirmCopyOperations = bool("confirmCopyOperations")
        s.confirmMoveOperations = bool("confirmMoveOperations")
        s.confirmDeleteOperations = bool("confirmDeleteOperations")
        s.permanentlyDeleteInsteadOfTrash = bool("permanentlyDeleteInsteadOfTrash")
        s.experimentalSandboxEnabled = bool(ExperimentalFlags.restrictFileAccessUserDefaultsKey)
        s.preferredSidebarWidth = defaults.object(forKey: "preferredSidebarWidth") as? Double ?? defaults.object(forKey: "sidebarWidth") as? Double
        s.lastLeftDirectory = defaults.url(forKey: "lastLeftDirectory")?.path
        s.lastRightDirectory = defaults.url(forKey: "lastRightDirectory")?.path
        s.startupLeftDirectory = defaults.url(forKey: "startupLeftDirectory")?.path
        s.startupRightDirectory = defaults.url(forKey: "startupRightDirectory")?.path
        s.scratchDirectory = defaults.url(forKey: "scratchDirectory")?.path
        s.scratchDirectoryIdentity = defaults.string(forKey: "scratchDirectoryIdentity")
        s.scratchDirectoryResolvedPath = defaults.string(forKey: "scratchDirectoryResolvedPath")
        s.defaultSortDescriptor = decoded("defaultSortDescriptor")
        s.leftPaneSortDescriptor = decoded("leftPaneSortDescriptor")
        s.rightPaneSortDescriptor = decoded("rightPaneSortDescriptor")
        s.leftPaneTabRestoration = decoded("leftPaneTabRestoration")
        s.rightPaneTabRestoration = decoded("rightPaneTabRestoration")
        s.fileColorScheme = decoded("fileColorScheme")
        return s
    }

    private func writeSnapshot(_ s: SettingsSnapshot) {
        set(s.appLanguage, Self.appLanguageDefaultsKey); set(s.defaultSidebarVisible, "defaultSidebarVisible")
        set(s.liquidGlassEnabled, "liquidGlassEnabled"); set(s.experimentalTerminalEnabled, "experimentalTerminalEnabled")
        set(s.hasAcknowledgedTerminalWarning, "hasAcknowledgedTerminalWarning"); set(s.defaultTerminalVisible, "defaultTerminalVisible")
        set(s.defaultSinglePaneMode, "defaultSinglePaneMode"); set(s.showHiddenFilesByDefault, "showHiddenFilesByDefault")
        setRaw(s.defaultPanePresentationMode?.rawValue, "defaultPanePresentationMode"); setRaw(s.leftPanePresentationMode?.rawValue, "leftPanePresentationMode"); setRaw(s.rightPanePresentationMode?.rawValue, "rightPanePresentationMode")
        setRaw(s.quickSearchMatchMode?.rawValue, "quickSearchMatchMode"); setRaw(s.quickSearchPresentation?.rawValue, "quickSearchPresentation")
        set(s.confirmCopyOperations, "confirmCopyOperations"); set(s.confirmMoveOperations, "confirmMoveOperations"); set(s.confirmDeleteOperations, "confirmDeleteOperations"); set(s.permanentlyDeleteInsteadOfTrash, "permanentlyDeleteInsteadOfTrash")
        set(s.experimentalSandboxEnabled, ExperimentalFlags.restrictFileAccessUserDefaultsKey); set(s.preferredSidebarWidth, "preferredSidebarWidth")
        setURL(s.lastLeftDirectory, "lastLeftDirectory"); setURL(s.lastRightDirectory, "lastRightDirectory")
        setURL(s.startupLeftDirectory, "startupLeftDirectory"); setURL(s.startupRightDirectory, "startupRightDirectory"); setURL(s.scratchDirectory, "scratchDirectory")
        set(s.scratchDirectoryIdentity, "scratchDirectoryIdentity"); set(s.scratchDirectoryResolvedPath, "scratchDirectoryResolvedPath")
        setEncoded(s.defaultSortDescriptor, "defaultSortDescriptor"); setEncoded(s.leftPaneSortDescriptor, "leftPaneSortDescriptor"); setEncoded(s.rightPaneSortDescriptor, "rightPaneSortDescriptor")
        setEncoded(s.leftPaneTabRestoration, "leftPaneTabRestoration"); setEncoded(s.rightPaneTabRestoration, "rightPaneTabRestoration"); setEncoded(s.fileColorScheme, "fileColorScheme")
    }

    private func bool(_ key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    private func enumValue<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String { defaults.string(forKey: key).flatMap(T.init(rawValue:)) }
    private func decoded<T: Decodable>(_ key: String) -> T? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func set<T>(_ value: T?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    private func setRaw(_ value: String?, _ key: String) { set(value, key) }
    private func setURL(_ path: String?, _ key: String) {
        if let path { defaults.set(URL(fileURLWithPath: path, isDirectory: true), forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    private func setEncoded<T: Encodable>(_ value: T?, _ key: String) { set(value.flatMap { try? JSONEncoder().encode($0) }, key) }

    /// v1 documents were intentionally sparse. Missing fields retain their
    /// UserDefaults value, while an empty optional-directory path means reset.
    private func migrated(_ incoming: SettingsSnapshot, over current: SettingsSnapshot) -> SettingsSnapshot {
        var result = current
        result.appLanguage = AppLanguage(rawValue: incoming.appLanguage ?? "")?.rawValue ?? AppLanguage.english.rawValue
        if let v = incoming.defaultSidebarVisible { result.defaultSidebarVisible = v }; if let v = incoming.liquidGlassEnabled { result.liquidGlassEnabled = v }
        if let v = incoming.experimentalTerminalEnabled { result.experimentalTerminalEnabled = v }; if let v = incoming.hasAcknowledgedTerminalWarning { result.hasAcknowledgedTerminalWarning = v }
        if let v = incoming.defaultTerminalVisible { result.defaultTerminalVisible = v }; if let v = incoming.defaultSinglePaneMode { result.defaultSinglePaneMode = v }; if let v = incoming.showHiddenFilesByDefault { result.showHiddenFilesByDefault = v }
        if let v = incoming.defaultPanePresentationMode { result.defaultPanePresentationMode = v }; if let v = incoming.leftPanePresentationMode { result.leftPanePresentationMode = v }; if let v = incoming.rightPanePresentationMode { result.rightPanePresentationMode = v }
        if let v = incoming.quickSearchMatchMode { result.quickSearchMatchMode = v }; if let v = incoming.quickSearchPresentation { result.quickSearchPresentation = v }
        if let v = incoming.confirmCopyOperations { result.confirmCopyOperations = v }; if let v = incoming.confirmMoveOperations { result.confirmMoveOperations = v }; if let v = incoming.confirmDeleteOperations { result.confirmDeleteOperations = v }; if let v = incoming.permanentlyDeleteInsteadOfTrash { result.permanentlyDeleteInsteadOfTrash = v }
#if DEBUG
        if let v = incoming.experimentalSandboxEnabled { result.experimentalSandboxEnabled = v }
#else
        result.experimentalSandboxEnabled = nil
#endif
        if let v = incoming.preferredSidebarWidth { result.preferredSidebarWidth = min(max(v, 220), 340) }
        if let v = incoming.lastLeftDirectory { result.lastLeftDirectory = v }; if let v = incoming.lastRightDirectory { result.lastRightDirectory = v }
        if let v = incoming.startupLeftDirectory { result.startupLeftDirectory = v.isEmpty ? nil : v }; if let v = incoming.startupRightDirectory { result.startupRightDirectory = v.isEmpty ? nil : v }; if let v = incoming.scratchDirectory { result.scratchDirectory = v.isEmpty ? nil : v }
        if let v = incoming.scratchDirectoryIdentity { result.scratchDirectoryIdentity = v }; if let v = incoming.scratchDirectoryResolvedPath { result.scratchDirectoryResolvedPath = v }
        if let v = incoming.defaultSortDescriptor { result.defaultSortDescriptor = v }; if let v = incoming.leftPaneSortDescriptor { result.leftPaneSortDescriptor = v }; if let v = incoming.rightPaneSortDescriptor { result.rightPaneSortDescriptor = v }
        if let v = incoming.leftPaneTabRestoration { result.leftPaneTabRestoration = v }; if let v = incoming.rightPaneTabRestoration { result.rightPaneTabRestoration = v }; if let v = incoming.fileColorScheme { result.fileColorScheme = v }
        return result
    }
}

private struct Document: Codable { let version: Int; let settings: SettingsSnapshot }

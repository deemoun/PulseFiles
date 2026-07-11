import AppKit

final class SettingsService {
    static var jsonSettingsURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("PulseFiles", isDirectory: true)
            .appendingPathComponent("Settings.json")
    }

    private let defaults: UserDefaults
    private let syncsJSON: Bool
    private let accessPolicyOverride: SandboxFileAccessPolicy?
    private let grantService: FolderAccessGrantService
    private let homeDirectoryProvider: () -> URL
    private let documentsDirectoryProvider: () -> URL
    private let downloadsDirectoryProvider: () -> URL
    private let applicationSupportDirectoryProvider: () -> URL
    private var isSyncingJSON = false
    private var runtimeTerminalVisible: Bool?

    init(
        defaults: UserDefaults = .standard,
        accessPolicy: SandboxFileAccessPolicy? = nil,
        homeDirectoryProvider: @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        documentsDirectoryProvider: @escaping () -> URL = {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        },
        downloadsDirectoryProvider: @escaping () -> URL = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        },
        applicationSupportDirectoryProvider: @escaping () -> URL = {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            return baseURL.appendingPathComponent("PulseFiles", isDirectory: true)
        }
    ) {
        self.defaults = defaults
        self.syncsJSON = defaults === UserDefaults.standard
        self.grantService = FolderAccessGrantService(defaults: defaults)
        self.grantService.resolveStoredBookmarks()
        self.accessPolicyOverride = accessPolicy
        self.homeDirectoryProvider = homeDirectoryProvider
        self.documentsDirectoryProvider = documentsDirectoryProvider
        self.downloadsDirectoryProvider = downloadsDirectoryProvider
        self.applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        if syncsJSON {
            importJSONIfChanged()
            writeSettingsJSONIfNeeded()
        }
    }

    var lastLeftDirectory: URL {
        get { directory(forKey: "lastLeftDirectory", fallback: defaultLeftDirectory) }
        set { set(newValue, forKey: "lastLeftDirectory") }
    }

    var lastRightDirectory: URL {
        get { directory(forKey: "lastRightDirectory", fallback: defaultRightDirectory) }
        set { set(newValue, forKey: "lastRightDirectory") }
    }

    var launchLeftDirectory: URL { startupLeftDirectory ?? lastLeftDirectory }
    var launchRightDirectory: URL { startupRightDirectory ?? lastRightDirectory }

    var startupLeftDirectory: URL? {
        get { optionalDirectory(forKey: "startupLeftDirectory") }
        set { setOptionalDirectory(newValue, forKey: "startupLeftDirectory") }
    }

    var startupRightDirectory: URL? {
        get { optionalDirectory(forKey: "startupRightDirectory") }
        set { setOptionalDirectory(newValue, forKey: "startupRightDirectory") }
    }

    var defaultSidebarVisible: Bool {
        get { defaults.object(forKey: "defaultSidebarVisible") as? Bool ?? defaults.object(forKey: "isSidebarVisible") as? Bool ?? true }
        set { set(newValue, forKey: "defaultSidebarVisible") }
    }

    var liquidGlassEnabled: Bool {
        get { defaults.object(forKey: LiquidGlassStyle.preferenceKey) as? Bool ?? false }
        set { set(newValue, forKey: LiquidGlassStyle.preferenceKey) }
    }

    var experimentalTerminalEnabled: Bool {
        get { defaults.object(forKey: "experimentalTerminalEnabled") as? Bool ?? false }
        set { set(newValue, forKey: "experimentalTerminalEnabled") }
    }

    var hasAcknowledgedTerminalWarning: Bool {
        get { defaults.object(forKey: "hasAcknowledgedTerminalWarning") as? Bool ?? false }
        set { set(newValue, forKey: "hasAcknowledgedTerminalWarning") }
    }

    var defaultTerminalVisible: Bool {
        get {
            guard experimentalTerminalEnabled else { return false }
            return defaults.object(forKey: "defaultTerminalVisible") as? Bool ?? false
        }
        set { set(experimentalTerminalEnabled && newValue, forKey: "defaultTerminalVisible") }
    }

    var defaultSinglePaneMode: Bool {
        get { defaults.object(forKey: "defaultSinglePaneMode") as? Bool ?? false }
        set { set(newValue, forKey: "defaultSinglePaneMode") }
    }

    var showHiddenFilesByDefault: Bool {
        get { defaults.object(forKey: "showHiddenFilesByDefault") as? Bool ?? false }
        set { set(newValue, forKey: "showHiddenFilesByDefault") }
    }

    var confirmCopyOperations: Bool {
        get { defaults.object(forKey: "confirmCopyOperations") as? Bool ?? true }
        set { set(newValue, forKey: "confirmCopyOperations") }
    }

    var confirmMoveOperations: Bool {
        get { defaults.object(forKey: "confirmMoveOperations") as? Bool ?? true }
        set { set(newValue, forKey: "confirmMoveOperations") }
    }

    var confirmDeleteOperations: Bool {
        get { defaults.object(forKey: "confirmDeleteOperations") as? Bool ?? true }
        set { set(newValue, forKey: "confirmDeleteOperations") }
    }

    var permanentlyDeleteInsteadOfTrash: Bool {
        get { defaults.object(forKey: "permanentlyDeleteInsteadOfTrash") as? Bool ?? false }
        set { set(newValue, forKey: "permanentlyDeleteInsteadOfTrash") }
    }

    #if DEBUG
    var experimentalSandboxEnabled: Bool {
        get { ExperimentalFlags.isSandboxRestrictionEnabled(defaults: defaults) }
        set { set(newValue, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey) }
    }
    #else
    var experimentalSandboxEnabled: Bool {
        get { false }
        set {
            defaults.removeObject(forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)
            writeSettingsJSONIfNeeded()
        }
    }
    #endif

    var fileColorScheme: FileColorScheme {
        get {
            guard let data = defaults.data(forKey: "fileColorScheme"),
                  let storedColors = try? JSONDecoder().decode([String: StoredColor].self, from: data) else {
                return .default
            }

            let colors = storedColors.reduce(into: [FileVisualCategory: NSColor]()) { partialResult, entry in
                guard let category = FileVisualCategory(rawValue: entry.key) else { return }
                partialResult[category] = entry.value.color
            }
            return FileColorScheme(colors: colors)
        }
        set {
            let storedColors = newValue.colors.reduce(into: [String: StoredColor]()) { partialResult, entry in
                partialResult[entry.key.rawValue] = StoredColor(color: entry.value)
            }
            guard let data = try? JSONEncoder().encode(storedColors) else { return }
            defaults.set(data, forKey: "fileColorScheme")
            writeSettingsJSONIfNeeded()
        }
    }

    func resetFileColorScheme() {
        defaults.removeObject(forKey: "fileColorScheme")
        writeSettingsJSONIfNeeded()
    }

    var folderAccessGrants: [FolderAccessGrant] {
        get { FolderAccessGrantService(defaults: defaults).grants }
        set {
            FolderAccessGrantService(defaults: defaults).grants = newValue
            writeSettingsJSONIfNeeded()
        }
    }

    var defaultSortDescriptor: FileSortDescriptor {
        get { sortDescriptor(forKey: "defaultSortDescriptor", fallback: FileSortDescriptor()) }
        set { setSortDescriptor(newValue, forKey: "defaultSortDescriptor") }
    }

    var preferredSidebarWidth: Double {
        get { defaults.object(forKey: "preferredSidebarWidth") as? Double ?? defaults.object(forKey: "sidebarWidth") as? Double ?? 260 }
        set { set(min(max(newValue, 220), 340), forKey: "preferredSidebarWidth") }
    }

    var isSidebarVisible: Bool {
        get { defaultSidebarVisible }
        set { defaultSidebarVisible = newValue }
    }

    var sidebarWidth: Double {
        get { preferredSidebarWidth }
        set { preferredSidebarWidth = newValue }
    }

    var isTerminalVisible: Bool {
        get {
            guard experimentalTerminalEnabled else { return false }
            return runtimeTerminalVisible ?? defaultTerminalVisible
        }
        set { runtimeTerminalVisible = experimentalTerminalEnabled && newValue }
    }

    private var accessPolicy: SandboxFileAccessPolicy {
        accessPolicyOverride ?? SandboxFileAccessPolicy(
            isEnabled: experimentalSandboxEnabled,
            rootURL: ExperimentalFlags.appSandboxRoot,
            grantService: grantService
        )
    }

    private var defaultLeftDirectory: URL {
        if experimentalSandboxEnabled {
            return accessPolicy.validatedDirectory(ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true))
        }

        return firstAccessibleDirectory(from: [
            homeDirectoryProvider(),
            documentsDirectoryProvider()
        ])
    }

    private var defaultRightDirectory: URL {
        if experimentalSandboxEnabled {
            return accessPolicy.validatedDirectory(ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true))
        }

        return firstAccessibleDirectory(from: [
            downloadsDirectoryProvider(),
            homeDirectoryProvider()
        ])
    }

    private func directory(forKey key: String, fallback: URL) -> URL {
        let url = defaults.url(forKey: key) ?? fallback
        return accessPolicy.validatedDirectory(url, fallback: fallback)
    }

    private func optionalDirectory(forKey key: String) -> URL? {
        defaults.url(forKey: key).map { accessPolicy.validatedDirectory($0) }
    }

    private func firstAccessibleDirectory(from preferredDirectories: [URL]) -> URL {
        for directory in preferredDirectories where accessPolicy.canAccess(directory) {
            return directory
        }

        let applicationSupportDirectory = applicationSupportDirectoryProvider()
        try? FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        if accessPolicy.canAccess(applicationSupportDirectory) {
            return applicationSupportDirectory
        }

        return accessPolicy.validatedDirectory(applicationSupportDirectory)
    }

    private func setOptionalDirectory(_ url: URL?, forKey key: String) {
        if let url {
            defaults.set(url, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        writeSettingsJSONIfNeeded()
    }

    private func sortDescriptor(forKey key: String, fallback: FileSortDescriptor) -> FileSortDescriptor {
        guard let data = defaults.data(forKey: key),
              let descriptor = try? JSONDecoder().decode(FileSortDescriptor.self, from: data) else {
            return fallback
        }
        return descriptor
    }

    private func setSortDescriptor(_ descriptor: FileSortDescriptor, forKey key: String) {
        guard let data = try? JSONEncoder().encode(descriptor) else { return }
        defaults.set(data, forKey: key)
        writeSettingsJSONIfNeeded()
    }

    private func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        writeSettingsJSONIfNeeded()
    }

    private func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
        writeSettingsJSONIfNeeded()
    }

    private func set(_ value: URL, forKey key: String) {
        defaults.set(value, forKey: key)
        writeSettingsJSONIfNeeded()
    }

    func importJSONIfChanged() {
        guard syncsJSON else { return }
        let url = Self.jsonSettingsURL
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else { return }
        let lastImport = defaults.object(forKey: "settingsJSONLastImportedModificationTime") as? Double ?? 0
        guard modificationDate.timeIntervalSince1970 > lastImport else { return }
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(SettingsJSONDocument.self, from: data) else { return }
        applyJSON(document.settings)
        defaults.set(modificationDate.timeIntervalSince1970, forKey: "settingsJSONLastImportedModificationTime")
        writeSettingsJSONIfNeeded()
    }

    @discardableResult
    func writeSettingsJSON() throws -> URL {
        let url = Self.jsonSettingsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let document = SettingsJSONDocument(version: 1, settings: makeJSONSettings())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            defaults.set(modificationDate.timeIntervalSince1970, forKey: "settingsJSONLastImportedModificationTime")
        }
        return url
    }

    private func writeSettingsJSONIfNeeded() {
        guard syncsJSON, !isSyncingJSON else { return }
        _ = try? writeSettingsJSON()
    }

    private var jsonExperimentalSandboxEnabled: Bool? {
        #if DEBUG
        experimentalSandboxEnabled
        #else
        nil
        #endif
    }

    private func makeJSONSettings() -> SettingsJSON {
        SettingsJSON(
            defaultSidebarVisible: defaultSidebarVisible,
            liquidGlassEnabled: liquidGlassEnabled,
            experimentalTerminalEnabled: experimentalTerminalEnabled,
            hasAcknowledgedTerminalWarning: hasAcknowledgedTerminalWarning,
            defaultTerminalVisible: defaultTerminalVisible,
            defaultSinglePaneMode: defaultSinglePaneMode,
            showHiddenFilesByDefault: showHiddenFilesByDefault,
            confirmCopyOperations: confirmCopyOperations,
            confirmMoveOperations: confirmMoveOperations,
            confirmDeleteOperations: confirmDeleteOperations,
            permanentlyDeleteInsteadOfTrash: permanentlyDeleteInsteadOfTrash,
            experimentalSandboxEnabled: jsonExperimentalSandboxEnabled,
            preferredSidebarWidth: preferredSidebarWidth,
            lastLeftDirectory: lastLeftDirectory.path,
            lastRightDirectory: lastRightDirectory.path,
            startupLeftDirectory: startupLeftDirectory?.path,
            startupRightDirectory: startupRightDirectory?.path,
            defaultSortDescriptor: defaultSortDescriptor,
            fileColorScheme: fileColorScheme.colors.reduce(into: [String: StoredColor]()) { partialResult, entry in
                partialResult[entry.key.rawValue] = StoredColor(color: entry.value)
            }
        )
    }

    private func applyJSON(_ settings: SettingsJSON) {
        isSyncingJSON = true
        defer { isSyncingJSON = false }

        if let value = settings.defaultSidebarVisible { defaults.set(value, forKey: "defaultSidebarVisible") }
        if let value = settings.liquidGlassEnabled { defaults.set(value, forKey: LiquidGlassStyle.preferenceKey) }
        if let value = settings.experimentalTerminalEnabled { defaults.set(value, forKey: "experimentalTerminalEnabled") }
        if let value = settings.hasAcknowledgedTerminalWarning { defaults.set(value, forKey: "hasAcknowledgedTerminalWarning") }
        if let value = settings.defaultTerminalVisible { defaults.set(value, forKey: "defaultTerminalVisible") }
        if let value = settings.defaultSinglePaneMode { defaults.set(value, forKey: "defaultSinglePaneMode") }
        if let value = settings.showHiddenFilesByDefault { defaults.set(value, forKey: "showHiddenFilesByDefault") }
        if let value = settings.confirmCopyOperations { defaults.set(value, forKey: "confirmCopyOperations") }
        if let value = settings.confirmMoveOperations { defaults.set(value, forKey: "confirmMoveOperations") }
        if let value = settings.confirmDeleteOperations { defaults.set(value, forKey: "confirmDeleteOperations") }
        if let value = settings.permanentlyDeleteInsteadOfTrash { defaults.set(value, forKey: "permanentlyDeleteInsteadOfTrash") }
        #if DEBUG
        if let value = settings.experimentalSandboxEnabled { defaults.set(value, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey) }
        #else
        if settings.experimentalSandboxEnabled != nil {
            defaults.removeObject(forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)
        }
        #endif
        if let value = settings.preferredSidebarWidth { defaults.set(min(max(value, 220), 340), forKey: "preferredSidebarWidth") }
        if let value = settings.lastLeftDirectory { defaults.set(URL(fileURLWithPath: value, isDirectory: true), forKey: "lastLeftDirectory") }
        if let value = settings.lastRightDirectory { defaults.set(URL(fileURLWithPath: value, isDirectory: true), forKey: "lastRightDirectory") }
        applyOptionalDirectory(settings.startupLeftDirectory, forKey: "startupLeftDirectory")
        applyOptionalDirectory(settings.startupRightDirectory, forKey: "startupRightDirectory")
        if let value = settings.defaultSortDescriptor { setSortDescriptor(value, forKey: "defaultSortDescriptor") }
        if let storedColors = settings.fileColorScheme {
            let colors = storedColors.reduce(into: [FileVisualCategory: NSColor]()) { partialResult, entry in
                guard let category = FileVisualCategory(rawValue: entry.key) else { return }
                partialResult[category] = entry.value.color
            }
            fileColorScheme = FileColorScheme(colors: colors)
        }
    }

    private func applyOptionalDirectory(_ path: String?, forKey key: String) {
        guard let path else { return }
        if path.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(URL(fileURLWithPath: path, isDirectory: true), forKey: key)
        }
    }
}


private struct SettingsJSONDocument: Codable {
    let version: Int
    let settings: SettingsJSON
}

private struct SettingsJSON: Codable {
    var defaultSidebarVisible: Bool?
    var liquidGlassEnabled: Bool?
    var experimentalTerminalEnabled: Bool?
    var hasAcknowledgedTerminalWarning: Bool?
    var defaultTerminalVisible: Bool?
    var defaultSinglePaneMode: Bool?
    var showHiddenFilesByDefault: Bool?
    var confirmCopyOperations: Bool?
    var confirmMoveOperations: Bool?
    var confirmDeleteOperations: Bool?
    var permanentlyDeleteInsteadOfTrash: Bool?
    var experimentalSandboxEnabled: Bool?
    var preferredSidebarWidth: Double?
    var lastLeftDirectory: String?
    var lastRightDirectory: String?
    var startupLeftDirectory: String?
    var startupRightDirectory: String?
    var defaultSortDescriptor: FileSortDescriptor?
    var fileColorScheme: [String: StoredColor]?
}

private struct StoredColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: NSColor) {
        let converted: NSColor?
        if let appearance = NSAppearance(named: .aqua) {
            var colorInAquaAppearance: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                colorInAquaAppearance = color.usingColorSpace(NSColorSpace.deviceRGB)
            }
            converted = colorInAquaAppearance
        } else {
            converted = color.usingColorSpace(NSColorSpace.deviceRGB)
        }
        let rgbColor = converted ?? NSColor.labelColor.usingColorSpace(NSColorSpace.deviceRGB) ?? NSColor(deviceWhite: 0, alpha: 1)
        red = Double(rgbColor.redComponent)
        green = Double(rgbColor.greenComponent)
        blue = Double(rgbColor.blueComponent)
        alpha = Double(rgbColor.alphaComponent)
    }

    var color: NSColor {
        NSColor(deviceRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

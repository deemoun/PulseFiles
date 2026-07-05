import AppKit

final class SettingsService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastLeftDirectory: URL {
        get { directory(forKey: "lastLeftDirectory", fallback: defaultLeftDirectory) }
        set { defaults.set(newValue, forKey: "lastLeftDirectory") }
    }

    var lastRightDirectory: URL {
        get { directory(forKey: "lastRightDirectory", fallback: defaultRightDirectory) }
        set { defaults.set(newValue, forKey: "lastRightDirectory") }
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
        set { defaults.set(newValue, forKey: "defaultSidebarVisible") }
    }

    var defaultTerminalVisible: Bool {
        get { defaults.object(forKey: "defaultTerminalVisible") as? Bool ?? defaults.object(forKey: "isTerminalVisible") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "defaultTerminalVisible") }
    }

    var defaultSinglePaneMode: Bool {
        get { defaults.object(forKey: "defaultSinglePaneMode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "defaultSinglePaneMode") }
    }

    var showHiddenFilesByDefault: Bool {
        get { defaults.object(forKey: "showHiddenFilesByDefault") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showHiddenFilesByDefault") }
    }

    var confirmCopyOperations: Bool {
        get { defaults.object(forKey: "confirmCopyOperations") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmCopyOperations") }
    }

    var confirmMoveOperations: Bool {
        get { defaults.object(forKey: "confirmMoveOperations") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmMoveOperations") }
    }

    var confirmDeleteOperations: Bool {
        get { defaults.object(forKey: "confirmDeleteOperations") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmDeleteOperations") }
    }

    var permanentlyDeleteInsteadOfTrash: Bool {
        get { defaults.object(forKey: "permanentlyDeleteInsteadOfTrash") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "permanentlyDeleteInsteadOfTrash") }
    }


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
        }
    }

    func resetFileColorScheme() {
        defaults.removeObject(forKey: "fileColorScheme")
    }

    var defaultSortDescriptor: FileSortDescriptor {
        get { sortDescriptor(forKey: "defaultSortDescriptor", fallback: FileSortDescriptor()) }
        set { setSortDescriptor(newValue, forKey: "defaultSortDescriptor") }
    }

    var preferredSidebarWidth: Double {
        get { defaults.object(forKey: "preferredSidebarWidth") as? Double ?? defaults.object(forKey: "sidebarWidth") as? Double ?? 220 }
        set { defaults.set(min(max(newValue, 180), 300), forKey: "preferredSidebarWidth") }
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
        get { defaultTerminalVisible }
        set { defaultTerminalVisible = newValue }
    }

    private var defaultLeftDirectory: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot ? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true) : FileManager.default.homeDirectoryForCurrentUser
    }

    private var defaultRightDirectory: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot ? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true) : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    private func directory(forKey key: String, fallback: URL) -> URL {
        let url = defaults.url(forKey: key) ?? fallback
        return ExperimentalFlags.restrictFileAccessToAppSandboxRoot ? SandboxFileAccessPolicy.current.validatedDirectory(url) : url
    }

    private func optionalDirectory(forKey key: String) -> URL? {
        defaults.url(forKey: key).map { ExperimentalFlags.restrictFileAccessToAppSandboxRoot ? SandboxFileAccessPolicy.current.validatedDirectory($0) : $0 }
    }

    private func setOptionalDirectory(_ url: URL?, forKey key: String) {
        if let url {
            defaults.set(url, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
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
    }
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
            converted = appearance.performAsCurrentDrawingAppearance {
                color.usingColorSpace(NSColorSpace.deviceRGB)
            }
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

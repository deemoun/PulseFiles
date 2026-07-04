import Foundation

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

    var showHiddenFilesByDefault: Bool {
        get { defaults.object(forKey: "showHiddenFilesByDefault") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showHiddenFilesByDefault") }
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
}

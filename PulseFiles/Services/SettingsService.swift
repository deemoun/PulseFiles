import Foundation

final class SettingsService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastLeftDirectory: URL {
        get {
            if ExperimentalFlags.restrictFileAccessToAppSandboxRoot {
                return defaults.url(forKey: "lastLeftDirectory").map(SandboxFileAccessPolicy.current.validatedDirectory)
                    ?? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Left Pane", isDirectory: true)
            }
            return defaults.url(forKey: "lastLeftDirectory") ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue, forKey: "lastLeftDirectory") }
    }

    var lastRightDirectory: URL {
        get {
            if ExperimentalFlags.restrictFileAccessToAppSandboxRoot {
                return defaults.url(forKey: "lastRightDirectory").map(SandboxFileAccessPolicy.current.validatedDirectory)
                    ?? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Right Pane", isDirectory: true)
            }
            return defaults.url(forKey: "lastRightDirectory") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        }
        set { defaults.set(newValue, forKey: "lastRightDirectory") }
    }

    var isSidebarVisible: Bool {
        get { defaults.object(forKey: "isSidebarVisible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "isSidebarVisible") }
    }

    var isTerminalVisible: Bool {
        get { defaults.object(forKey: "isTerminalVisible") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "isTerminalVisible") }
    }
}

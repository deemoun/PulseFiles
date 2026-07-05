import Foundation

enum ExperimentalFlags {
    static let restrictFileAccessUserDefaultsKey = "ExperimentalFlags.restrictFileAccessToAppSandboxRoot"

    static var restrictFileAccessToAppSandboxRoot: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--pulsefiles-disable-experimental-sandbox") {
            return false
        }
        if arguments.contains("--pulsefiles-enable-experimental-sandbox") {
            return true
        }

        let defaults = UserDefaults.standard
        guard defaults.object(forKey: restrictFileAccessUserDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: restrictFileAccessUserDefaultsKey)
    }

    static let sandboxRestrictionExplanation = "Browsing is restricted to the PulseFiles experimental sandbox while sandbox mode is enabled. Normal macOS favorites and folders outside this root may be hidden or unavailable."

    static var appSandboxRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PulseFiles", isDirectory: true)
            .appendingPathComponent("ExperimentalSandbox", isDirectory: true)
    }

    static func ensureAppSandboxRootExists() {
        guard restrictFileAccessToAppSandboxRoot else { return }
        let fileManager = FileManager.default
        let root = appSandboxRoot
        let folders = [
            root,
            root.appendingPathComponent("Left Pane", isDirectory: true),
            root.appendingPathComponent("Right Pane", isDirectory: true),
            root.appendingPathComponent("Projects", isDirectory: true),
            root.appendingPathComponent("Downloads", isDirectory: true)
        ]

        for folder in folders {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let readme = root.appendingPathComponent("README.txt")
        if !fileManager.fileExists(atPath: readme.path) {
            let text = """
            PulseFiles experimental sandbox

            File browsing is currently restricted to this app-owned test folder.
            Launch with --pulsefiles-disable-experimental-sandbox or set UserDefaults key ExperimentalFlags.restrictFileAccessToAppSandboxRoot to false when you are ready to test real folders.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
    }
}

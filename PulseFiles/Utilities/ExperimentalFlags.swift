import Foundation

enum ExperimentalFlags {
    static let restrictFileAccessUserDefaultsKey = "ExperimentalFlags.restrictFileAccessToAppSandboxRoot"

    static var restrictFileAccessToAppSandboxRoot: Bool {
        isSandboxRestrictionEnabled()
    }

    static func isSandboxRestrictionEnabled(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("--pulsefiles-disable-experimental-sandbox") {
            return false
        }

        #if DEBUG
        if arguments.contains("--pulsefiles-enable-experimental-sandbox") {
            return true
        }
        if defaults.object(forKey: restrictFileAccessUserDefaultsKey) != nil {
            return defaults.bool(forKey: restrictFileAccessUserDefaultsKey)
        }
        #endif

        return false
    }

    static var sandboxRestrictionExplanation: String { "Browsing is restricted to the PulseFiles experimental sandbox while sandbox mode is enabled. Normal macOS favorites and folders outside this root may be hidden or unavailable.".localized }

    static var appSandboxRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PulseFiles", isDirectory: true)
            .appendingPathComponent("ExperimentalSandbox", isDirectory: true)
    }

    static func ensureAppSandboxRootExists() {
        #if DEBUG
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
            In debug builds, launch with --pulsefiles-enable-experimental-sandbox or set UserDefaults key ExperimentalFlags.restrictFileAccessToAppSandboxRoot to true to test sandboxed browsing.
            Launch with --pulsefiles-disable-experimental-sandbox to force unrestricted browsing.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
        #endif
    }
}

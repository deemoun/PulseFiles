import AppKit

@main
@MainActor
enum PulseFilesApplication {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

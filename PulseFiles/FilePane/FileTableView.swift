import AppKit

protocol FileTableViewActionDelegate: AnyObject {
    func fileTableViewDidActivate(_ tableView: FileTableView)
    func fileTableView(_ tableView: FileTableView, didRequestLocation url: URL)
    func fileTableView(_ tableView: FileTableView, contextMenuForRow row: Int) -> NSMenu?
}

final class FileTableView: NSTableView {
    weak var actionDelegate: FileTableViewActionDelegate?

    override func mouseDown(with event: NSEvent) {
        actionDelegate?.fileTableViewDidActivate(self)
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        actionDelegate?.fileTableViewDidActivate(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        return actionDelegate?.fileTableView(self, contextMenuForRow: row)
    }

    override func keyDown(with event: NSEvent) {
        // Global commands are resolved by MainCommandRouter before the table receives the event.
        // These two locations are pane-only conveniences with no MainCommand representation.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == [.command, .shift], event.keyCode == 2 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.desktop)
            return
        }
        if flags == [.command, .shift], event.keyCode == 31 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.documents)
            return
        }
        super.keyDown(with: event)
    }
}

private enum ShortcutLocations {
    static var home: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? ExperimentalFlags.appSandboxRoot
            : FileManager.default.homeDirectoryForCurrentUser
    }

    static var desktop: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? ExperimentalFlags.appSandboxRoot
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static var documents: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Projects", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    static var downloads: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? ExperimentalFlags.appSandboxRoot.appendingPathComponent("Downloads", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    static var applications: URL {
        ExperimentalFlags.restrictFileAccessToAppSandboxRoot
            ? ExperimentalFlags.appSandboxRoot
            : URL(fileURLWithPath: "/Applications")
    }
}

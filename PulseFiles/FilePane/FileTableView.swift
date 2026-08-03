import AppKit

protocol FileTableViewActionDelegate: AnyObject {
    func fileTableViewDidActivate(_ tableView: FileTableView)
    func fileTableView(_ tableView: FileTableView, contextMenuForRow row: Int) -> NSMenu?
    func fileTableView(_ tableView: FileTableView, didFocusRow row: Int)
    func fileTableView(_ tableView: FileTableView, handleKeyDown event: NSEvent) -> Bool
}

final class FileTableView: NSTableView {
    weak var actionDelegate: FileTableViewActionDelegate?

    override func mouseDown(with event: NSEvent) {
        // Activation is intentionally before AppKit dispatches a double action
        // so command routing already targets this pane. Its delegate contract
        // must remain presentation-only: it may not reload or reorder rows.
        actionDelegate?.fileTableViewDidActivate(self)
        let row = row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if row >= 0 { actionDelegate?.fileTableView(self, didFocusRow: row) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        actionDelegate?.fileTableViewDidActivate(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        return actionDelegate?.fileTableView(self, contextMenuForRow: row)
    }

    override func keyDown(with event: NSEvent) {
        if actionDelegate?.fileTableView(self, handleKeyDown: event) == true { return }
        super.keyDown(with: event)
    }
}

enum ShortcutLocations {
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

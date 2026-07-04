import AppKit

protocol FileTableViewActionDelegate: AnyObject {
    func fileTableViewDidActivate(_ tableView: FileTableView)
    func fileTableViewDidRequestOpen(_ tableView: FileTableView)
    func fileTableViewDidRequestParent(_ tableView: FileTableView)
    func fileTableViewDidRequestBack(_ tableView: FileTableView)
    func fileTableViewDidRequestForward(_ tableView: FileTableView)
    func fileTableView(_ tableView: FileTableView, didRequestLocation url: URL)
    func fileTableViewDidRequestToggleHidden(_ tableView: FileTableView)
    func fileTableViewDidRequestTerminalToggle(_ tableView: FileTableView)
    func fileTableViewDidRequestNewFolder(_ tableView: FileTableView)
    func fileTableViewDidRequestNewFile(_ tableView: FileTableView)
    func fileTableViewDidRequestPaneSwitch(_ tableView: FileTableView)
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
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        if event.keyCode == 48 {
            actionDelegate?.fileTableViewDidRequestPaneSwitch(self)
            return
        }
        if shift && event.keyCode == 98 {
            actionDelegate?.fileTableViewDidRequestNewFile(self)
            return
        }
        if event.keyCode == 98 {
            actionDelegate?.fileTableViewDidRequestNewFolder(self)
            return
        }
        if command && event.keyCode == 50 {
            actionDelegate?.fileTableViewDidRequestTerminalToggle(self)
            return
        }
        if event.keyCode == 36 {
            actionDelegate?.fileTableViewDidRequestOpen(self)
            return
        }
        if event.keyCode == 51 || (command && event.keyCode == 126) {
            actionDelegate?.fileTableViewDidRequestParent(self)
            return
        }
        if command && event.keyCode == 33 {
            actionDelegate?.fileTableViewDidRequestBack(self)
            return
        }
        if command && event.keyCode == 30 {
            actionDelegate?.fileTableViewDidRequestForward(self)
            return
        }
        if command && shift && event.keyCode == 4 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.home)
            return
        }
        if command && shift && event.keyCode == 2 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.desktop)
            return
        }
        if command && shift && event.keyCode == 31 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.documents)
            return
        }
        if command && event.modifierFlags.contains(.option) && event.keyCode == 37 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.downloads)
            return
        }
        if command && shift && event.keyCode == 0 {
            actionDelegate?.fileTableView(self, didRequestLocation: ShortcutLocations.applications)
            return
        }
        if command && shift && event.charactersIgnoringModifiers == "." {
            actionDelegate?.fileTableViewDidRequestToggleHidden(self)
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

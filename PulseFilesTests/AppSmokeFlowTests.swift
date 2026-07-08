import AppKit
import Foundation
import XCTest
@testable import PulseFiles

@MainActor
final class AppSmokeFlowTests: XCTestCase {
    func testSmokeFlowsStayLogicBackedBecauseSwiftPMDoesNotProvideReliableAppKitXCUITestRunner() async throws {
        let app = try AppRobot.temporary()
        let leftDirectory = app.leftPane.viewModel.currentDirectory
        let rightDirectory = app.rightPane.viewModel.currentDirectory

        app.fileSystem.setItems([
            TestFileSystem.item(named: "alpha.txt", in: leftDirectory),
            TestFileSystem.item(named: "beta.md", in: leftDirectory),
            TestFileSystem.item(named: "Reports", in: leftDirectory, isDirectory: true)
        ], for: leftDirectory)
        app.fileSystem.setItems([
            TestFileSystem.item(named: "right-pane.txt", in: rightDirectory)
        ], for: rightDirectory)

        let launchedApp = await app.launch()
        launchedApp
            .expectLaunched()
            .expectPanesVisible()
            .expectAccessibilityIdentifiers()
            .expectActivePane(.left)
            .switchPane()
            .expectActivePane(.right)
            .switchPane()
            .expectActivePane(.left)
            .toggleSidebar()
            .expectSidebarVisible(false)
            .toggleSidebar()
            .expectSidebarVisible(true)

        app.rightPane
            .expectAccessibilityIdentifiers()

        XCTAssertEqual(app.commandBar.fieldAccessibilityIdentifier, AccessibilityIdentifiers.CommandBar.field)
        XCTAssertEqual(app.commandBar.listAccessibilityIdentifier, AccessibilityIdentifiers.CommandBar.list)
        XCTAssertEqual(app.sidebar.toggleAccessibilityIdentifier, AccessibilityIdentifiers.Toolbar.sidebarToggle)
        XCTAssertEqual(app.sidebar.listAccessibilityIdentifier, AccessibilityIdentifiers.Sidebar.list)
        XCTAssertEqual(app.terminal.panelAccessibilityIdentifier, AccessibilityIdentifiers.Terminal.panel)
        XCTAssertEqual(app.terminal.toggleAccessibilityIdentifier, AccessibilityIdentifiers.Toolbar.terminalToggle)

        app.leftPane
            .filter("alpha")
            .expectFilter("alpha")
            .expectVisibleItemNames(["alpha.txt"])

        app.commandBar
            .open()
            .expectOpen(true)
            .typeKnownCommand(.view)
            .expectExecuted([.open])

        app.terminal
            .expectEnabled(false)
            .expectVisibleByDefault(false)

        app.leftPane.select([leftDirectory.appendingPathComponent("alpha.txt")])
        app.requestDestructiveCommand(.trash)
            .expectPendingDestructiveConfirmation(.trash)
            .expectDestructiveMutationCount(0)
    }

    func testFileClipboardRoundTripPreservesOperationAndURLs() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PulseFilesTests.FileClipboard.\(UUID().uuidString)"))
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let urls = [
            URL(fileURLWithPath: "/tmp/PulseFiles/alpha.txt"),
            URL(fileURLWithPath: "/tmp/PulseFiles/beta.txt")
        ]

        clipboard.write(urls: urls, operation: .move)

        XCTAssertEqual(clipboard.read(), FileClipboard.Payload(urls: urls, operation: .move))
        XCTAssertGreaterThan(clipboard.changeCount, 0)
    }
}

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
            .expectActivePane(.left)
            .switchPane()
            .expectActivePane(.right)
            .switchPane()
            .expectActivePane(.left)
            .toggleSidebar()
            .expectSidebarVisible(false)
            .toggleSidebar()
            .expectSidebarVisible(true)

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
}

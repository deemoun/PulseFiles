import XCTest
@testable import PulseFiles
@testable import PulseFilesPane

@MainActor
final class PaneTabsTests: XCTestCase {
    func testEachTabOwnsIndependentBrowserState() throws {
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)
        let first = PaneTabState(currentDirectory: root, markedURLs: [root.appendingPathComponent("a")], focusedURL: root.appendingPathComponent("a"), searchQuery: "first", history: NavigationHistory(initialURL: root), sort: .init(key: .size), showsHiddenFiles: true)
        let other = PaneTabState(currentDirectory: second, searchQuery: "second", history: NavigationHistory(initialURL: second), sort: .init(key: .modified), showsHiddenFiles: false)
        var pane = PaneState(tabs: [first, other], activeTabID: first.id)

        pane.activeTabID = other.id

        XCTAssertEqual(pane.currentDirectory, second)
        XCTAssertEqual(pane.searchQuery, "second")
        XCTAssertEqual(pane.sort.key, .modified)
        XCTAssertTrue(pane.tabs[0].showsHiddenFiles)
        XCTAssertEqual(pane.tabs[0].markedURLs, first.markedURLs)
    }

    func testRestorationDeliberatelyOmitsTransientState() {
        let directory = URL(fileURLWithPath: "/tmp/restored", isDirectory: true)
        let tab = PaneTabState(currentDirectory: directory, markedURLs: [directory.appendingPathComponent("secret")], focusedURL: directory.appendingPathComponent("secret"), searchQuery: "private", history: NavigationHistory(initialURL: directory), sort: .init(key: .kind), showsHiddenFiles: true)

        let restored = PaneRestorationState(paneState: PaneState(tabs: [tab], activeTabID: tab.id))

        XCTAssertEqual(restored.tabs.map(\.directory), [directory])
        XCTAssertEqual(restored.tabs.first?.sort.key, .kind)
        XCTAssertEqual(restored.tabs.first?.showsHiddenFiles, true)
    }

    func testTabCommandsRouteToActivePaneAndFinalTabCannotClose() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let left = MainCommandRoutingPane(id: .left, currentDirectory: directory, tabCount: 2)
        let right = MainCommandRoutingPane(id: .right, currentDirectory: directory)
        let state = MainCommandRoutingState(leftPane: left, rightPane: right)

        XCTAssertEqual(MainCommandRouter().route(.newTab, in: state), .activePane(command: .newTab, pane: .left, urls: []))
        XCTAssertEqual(MainCommandRouter().route(.closeTab, in: state), .activePane(command: .closeTab, pane: .left, urls: []))
        var finalTabState = state
        finalTabState.leftPane.tabCount = 1
        XCTAssertEqual(MainCommandRouter().route(.closeTab, in: finalTabState), .disabled(command: .closeTab, reason: .lastTab))
    }

    func testApprovedShortcutsReserveCommandTForNewTab() {
        XCTAssertEqual(MainCommandShortcutRegistry.descriptor(for: .newTab).primaryLabel, "⌘T")
        XCTAssertEqual(MainCommandShortcutRegistry.descriptor(for: .togglePaneLayout).primaryLabel, "⌥⌘\\")
        XCTAssertEqual(MainCommandRouter().commandForKeyDown(keyCode: 17, command: true), .newTab)
        XCTAssertEqual(MainCommandRouter().commandForKeyDown(keyCode: 42, command: true, option: true), .togglePaneLayout)
    }

    func testRestoredTabsAreFilteredAtSandboxBoundaryAndFallBackSafely() throws {
        let sandbox = try SandboxFixture(testCase: self)
        let allowedID = UUID()
        let rejectedID = UUID()
        let restoration = PaneRestorationState(
            tabs: [
                .init(id: rejectedID, directory: sandbox.externalDirectory, sort: .init(), showsHiddenFiles: false),
                .init(id: allowedID, directory: sandbox.allowedDirectory, sort: .init(key: .size), showsHiddenFiles: true)
            ],
            activeTabID: rejectedID
        )

        let viewModel = FilePaneViewModel(initialDirectory: sandbox.allowedDirectory, restoration: restoration, fileSystem: TestFileSystem(), accessPolicy: sandbox.policy)

        XCTAssertEqual(viewModel.tabs.map(\.id), [allowedID])
        XCTAssertEqual(viewModel.activeTabID, allowedID)
        XCTAssertTrue(sandbox.policy.canAccess(viewModel.currentDirectory))
    }
}

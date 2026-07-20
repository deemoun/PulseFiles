import XCTest
@testable import PulseFiles

@MainActor
final class OpenWithApplicationDiscoveryTests: XCTestCase {
    func testSuccessfulLookupReplacesLoadingItemWithSortedApplications() async {
        let resolver = OpenWithMenuApplicationResolver(
            discovery: StubApplicationDiscovery(outcome: .success([
                URL(fileURLWithPath: "/Applications/Zebra.app"),
                URL(fileURLWithPath: "/Applications/Alpha.app")
            ]))
        )
        let fixture = makeMenuFixture()

        resolver.resolveApplications(
            for: fixture.fileURL,
            menuItem: fixture.menuItem,
            submenu: fixture.submenu,
            loadingItem: fixture.loadingItem,
            makeApplicationItem: { self.applicationMenuItem(for: $0) }
        )

        await waitForMenuUpdate()
        XCTAssertEqual(fixture.submenu.items.map(\.title), ["Default Application", "", "Alpha", "Zebra"])
        XCTAssertTrue(fixture.submenu.item(at: 0)?.isEnabled == true)
    }

    func testFailedLookupLeavesDefaultActionAndOmitsApplicationList() async {
        let resolver = OpenWithMenuApplicationResolver(
            discovery: StubApplicationDiscovery(outcome: .failure)
        )
        let fixture = makeMenuFixture()

        resolver.resolveApplications(
            for: fixture.fileURL,
            menuItem: fixture.menuItem,
            submenu: fixture.submenu,
            loadingItem: fixture.loadingItem,
            makeApplicationItem: { self.applicationMenuItem(for: $0) }
        )

        await waitForMenuUpdate()
        XCTAssertEqual(fixture.submenu.items.map(\.title), ["Default Application"])
        XCTAssertTrue(fixture.submenu.item(at: 0)?.isEnabled == true)
    }

    func testStaleMenuDoesNotReceiveLookupResult() async {
        let resolver = OpenWithMenuApplicationResolver(
            discovery: StubApplicationDiscovery(
                outcome: .success([URL(fileURLWithPath: "/Applications/Alpha.app")]),
                delay: .milliseconds(30)
            )
        )
        let fixture = makeMenuFixture()

        resolver.resolveApplications(
            for: fixture.fileURL,
            menuItem: fixture.menuItem,
            submenu: fixture.submenu,
            loadingItem: fixture.loadingItem,
            makeApplicationItem: { self.applicationMenuItem(for: $0) }
        )
        fixture.menuItem.submenu = NSMenu(title: "Replacement")

        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(fixture.submenu.items.map(\.title), ["Default Application", "Loading Applications…"])
    }

    private func makeMenuFixture() -> MenuFixture {
        let menuItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open With")
        let defaultItem = NSMenuItem(title: "Default Application", action: nil, keyEquivalent: "")
        let loadingItem = NSMenuItem(title: "Loading Applications…", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        submenu.addItem(defaultItem)
        submenu.addItem(loadingItem)
        menuItem.submenu = submenu
        return MenuFixture(menuItem: menuItem, submenu: submenu, loadingItem: loadingItem)
    }

    private func applicationMenuItem(for url: URL) -> NSMenuItem {
        NSMenuItem(title: url.deletingPathExtension().lastPathComponent, action: nil, keyEquivalent: "")
    }

    private func waitForMenuUpdate() async {
        try? await Task.sleep(for: .milliseconds(30))
    }
}

private struct MenuFixture {
    let fileURL = URL(fileURLWithPath: "/tmp/Document.txt")
    let menuItem: NSMenuItem
    let submenu: NSMenu
    let loadingItem: NSMenuItem
}

private struct StubApplicationDiscovery: OpenWithApplicationDiscovering {
    enum Outcome: Sendable {
        case success([URL])
        case failure
    }

    let outcome: Outcome
    let delay: Duration?

    init(outcome: Outcome, delay: Duration? = nil) {
        self.outcome = outcome
        self.delay = delay
    }

    func applicationURLs(for fileURL: URL) async throws -> [URL] {
        if let delay { try await Task.sleep(for: delay) }
        switch outcome {
        case .success(let urls): return urls
        case .failure: throw TestError.failed
        }
    }
}

private enum TestError: Error {
    case failed
}

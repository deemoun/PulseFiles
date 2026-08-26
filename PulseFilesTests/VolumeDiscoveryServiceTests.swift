// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class VolumeDiscoveryServiceTests: XCTestCase {
    func testScratchSidebarItemUsesConfiguredAccessibleDirectory() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchSidebarItemTests", testCase: self)
        let scratch = try fixture.folder("Personal Workspace")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root)
        let defaultsFixture = try IsolatedDefaultsFixture(prefix: "ScratchSidebarItemTests", testCase: self)
        let settings = SettingsService(defaults: defaultsFixture.defaults, accessPolicy: policy)
        settings.scratchDirectory = scratch
        let sidebar = SidebarViewController(
            recentLocations: RecentLocationService(defaults: defaultsFixture.defaults),
            bookmarkService: BookmarkService(defaults: defaultsFixture.defaults),
            settings: settings,
            accessPolicy: policy,
            volumeDiscovery: FixtureVolumeDiscovery(volumes: []),
            directorySizing: SidebarSizingFake()
        )

        let items = sidebar.scratchItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Scratch Folder")
        XCTAssertEqual(items.first?.url, scratch)
        XCTAssertEqual(items.first?.symbol, "tray.full")
        XCTAssertEqual(items.first?.group, "Temporary Workspace")
    }

    func testScratchSidebarItemOmitsUnsetAndInaccessibleDirectories() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchSidebarAccessTests", testCase: self)
        let outside = try TemporaryDirectoryFixture(named: "ScratchSidebarOutsideTests", testCase: self).folder("Outside")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root)

        XCTAssertTrue(SidebarViewController.scratchItems(directory: nil, accessPolicy: policy).isEmpty)
        XCTAssertTrue(SidebarViewController.scratchItems(directory: outside, accessPolicy: policy).isEmpty)
    }

    func testSortingUsesCaseInsensitiveDisplayName() {
        let volumes = [
            volume(name: "zeta", path: "/Volumes/zeta"),
            volume(name: "Alpha", path: "/Volumes/alpha"),
            volume(name: "beta", path: "/Volumes/beta")
        ]

        XCTAssertEqual(VolumeDiscoveryService.sortedVolumes(volumes).map(\.displayName), ["Alpha", "beta", "zeta"])
    }

    func testSidebarPresentationIncludesDeniedVolumesWithoutGrantingAccess() {
        let sandbox = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let policy = SandboxFileAccessPolicy(
            isEnabled: true,
            rootURL: sandbox,
            accessProbe: .init(fileExists: { _ in true }, isReadableFile: { _ in true }, isWritableFile: { _ in true })
        )
        let volumes = [
            volume(name: "Network Share", path: "/Volumes/network", local: false),
            volume(name: "Sandbox Disk", path: "/sandbox", total: 1_000, available: 250),
            volume(name: "Backup", path: "/Volumes/backup", removable: true, readOnly: true),
            volume(name: "", path: "/Volumes/unnamed")
        ]

        let items = SidebarViewController.deviceItems(volumes: volumes, accessPolicy: policy)

        XCTAssertEqual(items.map(\.title), ["Backup", "Network Share", "Sandbox Disk"])
        XCTAssertEqual(items.map(\.isAvailable), [false, false, true])
        XCTAssertEqual(items[0].symbol, "externaldrive")
        XCTAssertEqual(items[1].symbol, "network")
        XCTAssertTrue(items[0].subtitle?.contains("Permission required") == true)
        XCTAssertTrue(items[0].subtitle?.contains("Read-only") == true)
        XCTAssertTrue(items[2].subtitle?.contains("available of") == true)
    }

    @MainActor
    func testSidebarUsesInjectedVolumeDiscoveryData() async {
        let sandbox = URL(fileURLWithPath: "/sandbox", isDirectory: true)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandbox)
        let discovery = FixtureVolumeDiscovery(volumes: [volume(name: "Injected", path: "/sandbox")])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sidebar = SidebarViewController(
            recentLocations: RecentLocationService(defaults: defaults),
            bookmarkService: BookmarkService(defaults: defaults),
            settings: SettingsService(defaults: defaults, accessPolicy: policy),
            accessPolicy: policy,
            volumeDiscovery: discovery,
            directorySizing: SidebarSizingFake()
        )

        _ = sidebar.view
        await Task.yield()
        XCTAssertEqual(sidebar.deviceItems().map(\.title), ["Injected"])
    }

    func testVolumePresentationSelectsInternalAndOpticalSymbols() {
        XCTAssertEqual(SidebarViewController.volumeSymbol(for: volume(name: "System", path: "/")), "internaldrive")
        XCTAssertEqual(SidebarViewController.volumeSymbol(for: volume(name: "DVD", path: "/Volumes/DVD")), "opticaldiscdrive")
    }

    @MainActor
    func testVolumeChangeMonitorPublishesFastSnapshotThenFreshMountedVolumeLists() async {
        let discovery = MutableVolumeDiscovery()
        discovery.volumes = [volume(name: "Existing", path: "/")]
        let center = NotificationCenter()
        let monitor = VolumeChangeMonitor(discovery: discovery, notificationCenter: center)
        var published: [VolumeChange] = []
        monitor.onVolumesChanged = { published.append($0) }
        await Task.yield()

        discovery.volumes = [volume(name: "Existing", path: "/"), volume(name: "Mounted", path: "/Volumes/Mounted")]
        center.post(name: NSWorkspace.didMountNotification, object: nil)
        XCTAssertEqual(published.last?.previous.map(\.displayName), ["Existing"])
        XCTAssertEqual(published.last?.current.map(\.displayName), ["Existing"])
        await Task.yield()

        XCTAssertEqual(published.last?.previous.map(\.displayName), ["Existing"])
        XCTAssertEqual(published.last?.current.map(\.displayName), ["Existing", "Mounted"])
    }

    func testPaneRouterIgnoresUnrelatedMountEvents() {
        let change = VolumeChange(
            previous: [volume(name: "System", path: "/")],
            current: [volume(name: "System", path: "/"), volume(name: "Backup", path: "/Volumes/Backup")]
        )

        let actions = VolumeChangePaneRefreshRouter.actions(
            for: [URL(fileURLWithPath: "/Users/example", isDirectory: true)],
            change: change,
            isReachable: { _ in true }
        )

        XCTAssertEqual(actions, [.none])
    }

    func testPaneRouterFallsBackForEjectedActiveVolume() {
        let removedRoot = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let activeDirectory = removedRoot.appendingPathComponent("Projects", isDirectory: true)
        let change = VolumeChange(previous: [volume(name: "Backup", path: removedRoot.path)], current: [])

        let actions = VolumeChangePaneRefreshRouter.actions(
            for: [activeDirectory],
            change: change,
            isReachable: { $0 != activeDirectory }
        )

        XCTAssertEqual(actions, [.fallBack])
    }

    func testPaneRouterRevalidatesChangedNetworkVolume() {
        let networkRoot = "/Volumes/Share"
        let change = VolumeChange(
            previous: [volume(name: "Share", path: networkRoot, local: false, readOnly: true)],
            current: [volume(name: "Share", path: networkRoot, local: false, readOnly: false)]
        )

        let actions = VolumeChangePaneRefreshRouter.actions(
            for: [URL(fileURLWithPath: networkRoot, isDirectory: true).appendingPathComponent("Team", isDirectory: true)],
            change: change,
            isReachable: { _ in true }
        )

        XCTAssertEqual(actions, [.revalidate])
    }

    private func volume(name: String, path: String, removable: Bool = false, local: Bool = true, readOnly: Bool = false, total: Int64? = nil, available: Int64? = nil) -> Volume {
        Volume(url: URL(fileURLWithPath: path, isDirectory: true), displayName: name, isRemovable: removable, isLocal: local, isNetwork: !local, isReadOnly: readOnly, totalCapacity: total, availableCapacity: available)
    }

    private struct FixtureVolumeDiscovery: VolumeDiscovering {
        let volumes: [Volume]

        func mountedVolumes() async -> [Volume] { volumes }
    }

    private final class MutableVolumeDiscovery: VolumeDiscovering {
        var volumes: [Volume] = []
        func mountedVolumes() async -> [Volume] { volumes }
    }
}

private struct SidebarSizingFake: DirectorySizing {
    func size(of root: URL) async throws -> DirectorySizeResult {
        DirectorySizeResult(bytes: 0, completeness: .complete)
    }
}

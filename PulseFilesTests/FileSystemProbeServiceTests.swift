import XCTest
@testable import PulseFiles

final class FileSystemProbeServiceTests: XCTestCase {
    func testDeadlineReturnsUnavailableWithoutWaitingForSlowFilesystem() async {
        let probe = FileSystemProbeService(
            existsOperation: { _ in Thread.sleep(forTimeInterval: 0.2); return true },
            directoryOperation: { _ in false },
            volumeOperation: { _ in nil }
        )

        let answer = await probe.exists(URL(fileURLWithPath: "/slow"), deadline: .milliseconds(10))
        XCTAssertEqual(answer, .unavailable)
    }

    func testVolumeIdentifierReportsDisappearedVolumeAsUnavailableIdentity() async {
        let probe = FileSystemProbeService(
            existsOperation: { _ in false },
            directoryOperation: { _ in false },
            volumeOperation: { _ in nil }
        )

        let answer = await probe.volumeIdentifier(URL(fileURLWithPath: "/Volumes/Ejected"), deadline: .milliseconds(50))
        XCTAssertEqual(answer, .value(nil))
    }

    func testAsyncRouterFallsBackWhenProbeCannotReachEjectedDirectory() async {
        let directory = URL(fileURLWithPath: "/Volumes/Ejected/Work", isDirectory: true)
        let change = VolumeChange(previous: [Volume(url: URL(fileURLWithPath: "/Volumes/Ejected", isDirectory: true), displayName: "Ejected", isRemovable: true, isLocal: true, isNetwork: false, isReadOnly: false)], current: [])

        let actions = await VolumeChangePaneRefreshRouter.actions(for: [directory], change: change) { _ in .unavailable }
        XCTAssertEqual(actions, [.fallBack])
    }

    @MainActor
    func testProbeCacheDoesNotPublishStaleResultAfterAnUnavailableAnswer() async {
        let probe = DelayedProbe()
        let cache = FileSystemProbeCache(probe: probe, deadline: .milliseconds(5))
        let url = URL(fileURLWithPath: "/Volumes/Slow", isDirectory: true)
        cache.requestDirectory(url)
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertNil(cache.directoryValue(for: url))
    }
}

private struct DelayedProbe: FileSystemProbing {
    func exists(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> { .unavailable }
    func isDirectory(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<Bool> {
        try? await Task.sleep(for: .milliseconds(50))
        return .value(true)
    }
    func volumeIdentifier(_ url: URL, deadline: Duration) async -> FileSystemProbeAnswer<String?> { .unavailable }
}

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

final class FileSystemOperationSchedulerTests: XCTestCase {
    func testRepeatedTimedOutProbesStopStartingAfterAbandonedLimit() async {
        let scheduler = FileSystemOperationScheduler(configuration: .init(maximumConcurrentOperations: 2, maximumQueuedOperations: 4, maximumAbandonedOperations: 2))
        let probe = FileSystemProbeService(
            existsOperation: { _ in Thread.sleep(forTimeInterval: 0.2); return true },
            directoryOperation: { _ in false },
            volumeOperation: { _ in nil },
            scheduler: scheduler
        )

        async let first = probe.exists(URL(fileURLWithPath: "/slow-1"), deadline: .milliseconds(5))
        async let second = probe.exists(URL(fileURLWithPath: "/slow-2"), deadline: .milliseconds(5))
        let firstAnswer = await first
        let secondAnswer = await second
        XCTAssertEqual(firstAnswer, .unavailable)
        XCTAssertEqual(secondAnswer, .unavailable)
        try? await Task.sleep(for: .milliseconds(10))

        let thirdAnswer = await probe.exists(URL(fileURLWithPath: "/slow-3"), deadline: .milliseconds(50))
        let statistics = await scheduler.statistics()
        XCTAssertEqual(thirdAnswer, .unavailable)
        XCTAssertEqual(statistics.abandoned, 2)
    }

    func testCancellationRemovesQueuedWorkWithoutStartingIt() async {
        let scheduler = FileSystemOperationScheduler(configuration: .init(maximumConcurrentOperations: 1, maximumQueuedOperations: 2, maximumAbandonedOperations: 1))
        let started = LockedCounter()
        let blocker = Task {
            try? await scheduler.submit(priority: .visiblePane) {
                started.increment()
                Thread.sleep(forTimeInterval: 0.15)
                return true
            }
        }
        while started.value == 0 { await Task.yield() }
        let queued = Task {
            try await scheduler.submit(priority: .probe) {
                started.increment()
                return true
            }
        }
        queued.cancel()
        _ = await queued.result
        _ = await blocker.result
        XCTAssertEqual(started.value, 1)
        let statistics = await scheduler.statistics()
        XCTAssertEqual(statistics.staleOperations, 1)
    }

    func testQueueSaturationAndRecoveryAfterBlockedOperationCompletes() async {
        let scheduler = FileSystemOperationScheduler(configuration: .init(maximumConcurrentOperations: 1, maximumQueuedOperations: 1, maximumAbandonedOperations: 1))
        let gate = DispatchSemaphore(value: 0)
        let blocker = Task { try? await scheduler.submit(priority: .visiblePane) { gate.wait(); return 1 } }
        try? await Task.sleep(for: .milliseconds(10))
        let queued = Task { try? await scheduler.submit(priority: .probe) { 2 } }
        try? await Task.sleep(for: .milliseconds(10))
        do {
            _ = try await scheduler.submit(priority: .probe) { 3 }
            XCTFail("Expected saturated scheduler queue")
        } catch let rejection as FileSystemOperationScheduler.Rejection {
            XCTAssertEqual(rejection, .queueFull)
        } catch { XCTFail("Unexpected error: \(error)") }

        gate.signal()
        _ = await blocker.value
        let queuedValue = await queued.value
        let recoveredValue = try? await scheduler.submit(priority: .visiblePane) { 4 }
        XCTAssertEqual(queuedValue, 2)
        XCTAssertEqual(recoveredValue, 4)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    func increment() { lock.lock(); storage += 1; lock.unlock() }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFiles

final class DirectoryMonitorTests: XCTestCase {
    func testRapidStartStopStartIgnoresEventFromOlderSourceGeneration() {
        let factory = FakeDirectoryMonitorSourceFactory()
        let scheduler = ManualDirectoryMonitorDebounceScheduler()
        let monitor = DirectoryMonitor(sourceFactory: factory, debounceScheduler: scheduler)
        var changes = 0
        monitor.onChange = { changes += 1 }

        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/first"))
        let firstSource = factory.sources[0]
        monitor.stop()
        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/second"))
        let secondSource = factory.sources[1]

        firstSource.fireEvent()
        XCTAssertTrue(scheduler.workItems.isEmpty)

        secondSource.fireEvent()
        XCTAssertEqual(scheduler.workItems.count, 1)
        scheduler.workItems[0].run()
        drainMainQueue()

        XCTAssertEqual(changes, 1)
        XCTAssertTrue(firstSource.wasCancelled)
    }

    func testDebouncedCallbackQueuedBeforeRestartCannotNotifyNewMonitor() {
        let factory = FakeDirectoryMonitorSourceFactory()
        let scheduler = ManualDirectoryMonitorDebounceScheduler()
        let monitor = DirectoryMonitor(sourceFactory: factory, debounceScheduler: scheduler)
        var changes = 0
        monitor.onChange = { changes += 1 }

        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/first"))
        factory.sources[0].fireEvent()
        XCTAssertEqual(scheduler.workItems.count, 1)

        // Run the debouncer so it queues its main-thread delivery, then replace the
        // monitor before that delivery can execute.
        scheduler.workItems[0].run()
        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/second"))
        drainMainQueue()

        XCTAssertEqual(changes, 0)
    }

    func testStopSynchronouslyCancelsPendingDebouncedNotification() {
        let factory = FakeDirectoryMonitorSourceFactory()
        let scheduler = ManualDirectoryMonitorDebounceScheduler()
        let monitor = DirectoryMonitor(sourceFactory: factory, debounceScheduler: scheduler)
        var changes = 0
        monitor.onChange = { changes += 1 }

        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/first"))
        factory.sources[0].fireEvent()
        let pendingWork = try! XCTUnwrap(scheduler.workItems.first)

        monitor.stop()

        XCTAssertTrue(pendingWork.wasCancelled)
        pendingWork.run() // Simulate a work item that had already become runnable.
        drainMainQueue()
        XCTAssertEqual(changes, 0)
    }

    func testCancelledEarlierDebounceCannotOvertakeNewerEvent() {
        let factory = FakeDirectoryMonitorSourceFactory()
        let scheduler = ManualDirectoryMonitorDebounceScheduler()
        let monitor = DirectoryMonitor(sourceFactory: factory, debounceScheduler: scheduler)
        var changes = 0
        monitor.onChange = { changes += 1 }

        monitor.startMonitoring(URL(fileURLWithPath: "/tmp/first"))
        factory.sources[0].fireEvent()
        let earlierWork = try! XCTUnwrap(scheduler.workItems.first)
        factory.sources[0].fireEvent()
        let latestWork = try! XCTUnwrap(scheduler.workItems.last)

        earlierWork.run()
        latestWork.run()
        drainMainQueue()

        XCTAssertTrue(earlierWork.wasCancelled)
        XCTAssertEqual(changes, 1)
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }
}

private final class FakeDirectoryMonitorSourceFactory: DirectoryMonitorSourceFactory {
    private(set) var sources: [FakeDirectoryMonitorSource] = []

    func makeSource(for url: URL, queue: DispatchQueue) -> DirectoryMonitorSourceHandle? {
        let source = FakeDirectoryMonitorSource()
        sources.append(source)
        return DirectoryMonitorSourceHandle(fileDescriptor: -1, source: source)
    }
}

private final class FakeDirectoryMonitorSource: DirectoryMonitorSource {
    private var eventHandler: (() -> Void)?
    private(set) var wasCancelled = false

    func setEventHandler(_ handler: @escaping () -> Void) { eventHandler = handler }
    func setCancelHandler(_ handler: @escaping () -> Void) {}
    func resume() {}
    func cancel() { wasCancelled = true }
    func fireEvent() { eventHandler?() }
}

private final class ManualDirectoryMonitorDebounceScheduler: DirectoryMonitorDebounceScheduling {
    private(set) var workItems: [ManualDirectoryMonitorDebounceWork] = []

    func schedule(after delay: DispatchTimeInterval, on queue: DispatchQueue, _ action: @escaping () -> Void) -> DirectoryMonitorDebounceWork {
        let work = ManualDirectoryMonitorDebounceWork(action: action)
        workItems.append(work)
        return work
    }
}

private final class ManualDirectoryMonitorDebounceWork: DirectoryMonitorDebounceWork {
    private let action: () -> Void
    private(set) var wasCancelled = false

    init(action: @escaping () -> Void) { self.action = action }
    func cancel() { wasCancelled = true }
    func run() { action() }
}

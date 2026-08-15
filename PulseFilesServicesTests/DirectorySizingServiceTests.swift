import Foundation
import XCTest
@testable import PulseFilesServices

final class DirectorySizingServiceTests: XCTestCase {
    func testPolicyRejectionDoesNotScheduleTraversal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let traversed = LockedInt()
        let service = DirectorySizingService(
            accessPolicy: SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.root),
            traversal: { _, _, _ in traversed.increment(); return .init(bytes: 0, completeness: .complete) }
        )

        do { _ = try await service.size(of: outside); XCTFail("Expected rejection") }
        catch is SandboxAccessError { }
        XCTAssertEqual(traversed.value, 0)
    }

    func testCancellationIsObservedByBlockingTraversal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let started = DispatchSemaphore(value: 0)
        let service = fixture.service { _, _, token in
            started.signal()
            while true { try token.checkCancellation(); Thread.sleep(forTimeInterval: 0.001) }
        }
        let task = Task { try await service.size(of: fixture.root) }
        started.wait()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testPartialTraversalIsPreservedAsLowerBound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = fixture.service { _, _, _ in
            DirectorySizeResult(bytes: 123, completeness: .partial(skippedItemCount: 2))
        }
        XCTAssertEqual(
            try await service.size(of: fixture.root),
            DirectorySizeResult(bytes: 123, completeness: .partial(skippedItemCount: 2))
        )
    }

    func testSchedulerSaturationIsReported() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scheduler = FileSystemOperationScheduler(configuration: .init(
            maximumConcurrentOperations: 1, maximumQueuedOperations: 2,
            maximumAbandonedOperations: 1, maximumConcurrentInspections: 1,
            maximumQueuedInspections: 0
        ))
        let gate = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let service = DirectorySizingService(
            accessPolicy: fixture.policy, scheduler: scheduler,
            traversal: { _, _, _ in started.signal(); gate.wait(); return .init(bytes: 1, completeness: .complete) }
        )
        let first = Task { try? await service.size(of: fixture.root) }
        started.wait()
        do { _ = try await service.size(of: fixture.root); XCTFail("Expected saturation") }
        catch let rejection as FileSystemOperationScheduler.Rejection {
            XCTAssertEqual(rejection, .inspectionQueueFull)
        }
        gate.signal(); _ = await first.value
    }
}

private struct Fixture {
    let root: URL
    let policy: SandboxFileAccessPolicy
    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
    }
    func service(traversal: @escaping DirectorySizingService.Traversal) -> DirectorySizingService {
        DirectorySizingService(accessPolicy: policy, scheduler: FileSystemOperationScheduler(), traversal: traversal)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    func increment() { lock.lock(); storage += 1; lock.unlock() }
}

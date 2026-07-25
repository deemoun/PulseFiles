import XCTest
@testable import PulseFiles

final class StagingOwnershipServiceTests: XCTestCase {
    private var root: URL!
    private var registry: StagingOwnershipRegistry!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = StagingOwnershipRegistry(url: root.appendingPathComponent("registry.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testInventoryClassifiesStaleCompletedButNeverActiveOperation() throws {
        let stale = try makeRecord(name: "stale", state: .completed, date: .distantPast)
        let active = try makeRecord(name: "active", state: .active, date: .distantPast)
        let recent = try makeRecord(name: "recent", state: .completed, date: Date())
        [stale, active, recent].forEach(registry.register)

        let inventory = service().inventory(olderThan: Date().addingTimeInterval(-3600), includeLegacyReview: false)

        XCTAssertEqual(inventory.candidates.map(\.record.operationID), [stale.operationID])
    }

    func testIdentityMismatchIsNotOfferedOrDeleted() async throws {
        let record = try makeRecord(name: "replaced", state: .completed, stagingIdentity: "old-identity")
        registry.register(record)
        let cleanup = service()

        let inventory = cleanup.inventory(includeLegacyReview: false)
        let result = await cleanup.cleanup([.init(record: record, byteCount: 0)])

        XCTAssertTrue(inventory.candidates.isEmpty)
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
    }

    func testSandboxRejectionIsReportedAndItemRemainsRegistered() async throws {
        let record = try makeRecord(name: "outside", state: .completed)
        registry.register(record)
        let deniedRoot = root.appendingPathComponent("different-root")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: deniedRoot)
        let cleanup = service(policy: policy)

        let result = await cleanup.cleanup([.init(record: record, byteCount: 0)])

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertEqual(registry.records.count, 1)
    }

    func testPartialCleanupFailureRemovesOnlySuccessfulRegistryEntry() async throws {
        let first = try makeRecord(name: "first", state: .completed)
        let second = try makeRecord(name: "second", state: .completed)
        [first, second].forEach(registry.register)
        let cleanup = service(remove: { url in
            if url == second.stagingURL { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })

        let result = await cleanup.cleanup([.init(record: first, byteCount: 0), .init(record: second, byteCount: 0)])

        XCTAssertEqual(result.removed, [first.stagingURL])
        XCTAssertEqual(result.failures.map(\.url), [second.stagingURL])
        XCTAssertEqual(registry.records.map(\.operationID), [second.operationID])
    }

    func testInventoryPrunesOnlyMissingRegistryEntries() throws {
        let existing = try makeRecord(name: "existing", state: .active)
        let missing = StagingOwnershipRecord(operationID: UUID(), stagingURL: root.appendingPathComponent("missing"), createdAt: .distantPast, destinationURL: existing.destinationURL, stagingIdentity: "missing", destinationIdentity: "destination", state: .completed)
        [existing, missing].forEach(registry.register)

        _ = service().inventory(includeLegacyReview: false)

        XCTAssertEqual(registry.records.map(\.operationID), [existing.operationID])
    }

    func testSimilarlyNamedUserFileIsReviewOnlyAndNeverAutomaticallyRemoved() async throws {
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let registered = try makeRecord(name: "registered", state: .active, destination: destination)
        registry.register(registered)
        let userFile = root.appendingPathComponent(".pulsefiles-copy-user-not-owned")
        try Data("mine".utf8).write(to: userFile)
        let cleanup = service()

        let startupResult = await cleanup.cleanupOnStartup(now: .distantFuture)
        let review = cleanup.inventory().legacyItemsForReview

        XCTAssertTrue(startupResult.removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
        // The migration is one-time; whether first observed by this call or startup,
        // a prefix match is never promoted into an owned cleanup candidate.
        XCTAssertTrue(review.isEmpty || review == [userFile])
    }

    private func makeRecord(name: String, state: StagingOperationState, date: Date = .distantPast, stagingIdentity: String? = nil, destination: URL? = nil) throws -> StagingOwnershipRecord {
        let staging = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let destination = destination ?? root
        return .init(operationID: UUID(), stagingURL: staging, createdAt: date, destinationURL: destination, stagingIdentity: stagingIdentity ?? staging.path, destinationIdentity: destination.path, state: state)
    }

    private func service(policy: SandboxFileAccessPolicy? = nil, remove: ((URL) throws -> Void)? = nil) -> StagingCleanupService {
        StagingCleanupService(
            registry: registry,
            accessPolicy: policy ?? SandboxFileAccessPolicy(isEnabled: true, rootURL: root),
            identity: { $0.path },
            remove: remove
        )
    }
}

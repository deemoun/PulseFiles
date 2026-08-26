// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

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
        try [stale, active, recent].forEach { try registry.register($0) }

        let inventory = try service().inventory(olderThan: Date().addingTimeInterval(-3600), includeLegacyReview: false)

        XCTAssertEqual(inventory.candidates.map(\.record.operationID), [stale.operationID])
    }

    func testIdentityMismatchIsNotOfferedOrDeleted() async throws {
        let record = try makeRecord(name: "replaced", state: .completed, stagingIdentity: "old-identity")
        try registry.register(record)
        let cleanup = service()

        let inventory = try cleanup.inventory(includeLegacyReview: false)
        let result = await cleanup.cleanup([.init(record: record, byteCount: 0)])

        XCTAssertTrue(inventory.candidates.isEmpty)
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
    }

    func testSandboxRejectionIsReportedAndItemRemainsRegistered() async throws {
        let record = try makeRecord(name: "outside", state: .completed)
        try registry.register(record)
        let deniedRoot = root.appendingPathComponent("different-root")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: deniedRoot)
        let cleanup = service(policy: policy)

        let result = await cleanup.cleanup([.init(record: record, byteCount: 0)])

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertEqual(try registry.records.count, 1)
    }

    func testPartialCleanupFailureRemovesOnlySuccessfulRegistryEntry() async throws {
        let first = try makeRecord(name: "first", state: .completed)
        let second = try makeRecord(name: "second", state: .completed)
        try [first, second].forEach { try registry.register($0) }
        let cleanup = service(remove: { url in
            if url == second.stagingURL { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })

        let result = await cleanup.cleanup([.init(record: first, byteCount: 0), .init(record: second, byteCount: 0)])

        XCTAssertEqual(result.removed, [first.stagingURL])
        XCTAssertEqual(result.failures.map(\.url), [second.stagingURL])
        XCTAssertEqual(try registry.records.map(\.operationID), [second.operationID])
    }

    func testInventoryPrunesOnlyMissingRegistryEntries() throws {
        let existing = try makeRecord(name: "existing", state: .active)
        let missing = StagingOwnershipRecord(operationID: UUID(), stagingURL: root.appendingPathComponent("missing"), createdAt: .distantPast, destinationURL: existing.destinationURL, stagingIdentity: "missing", destinationIdentity: "destination", state: .completed)
        try [existing, missing].forEach { try registry.register($0) }

        _ = try service().inventory(includeLegacyReview: false)

        XCTAssertEqual(try registry.records.map(\.operationID), [existing.operationID])
    }

    func testSimilarlyNamedUserFileIsReviewOnlyAndNeverAutomaticallyRemoved() async throws {
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let registered = try makeRecord(name: "registered", state: .active, destination: destination)
        try registry.register(registered)
        let userFile = root.appendingPathComponent(".pulsefiles-copy-user-not-owned")
        try Data("mine".utf8).write(to: userFile)
        let cleanup = service()

        let startupResult = await cleanup.cleanupOnStartup(now: .distantFuture)
        let review = try cleanup.inventory().legacyItemsForReview

        XCTAssertTrue(startupResult.removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
        // The migration is one-time; whether first observed by this call or startup,
        // a prefix match is never promoted into an owned cleanup candidate.
        XCTAssertTrue(review.isEmpty || review == [userFile])
    }

    func testRegistrationSurfacesEncodingFailureWithoutWriting() throws {
        var writes = 0
        let failing = StagingOwnershipRegistry(
            url: root.appendingPathComponent("encode.json"),
            encode: { _ in throw CocoaError(.fileWriteInapplicableStringEncoding) },
            persist: { _ in writes += 1 }
        )
        let record = try makeRecord(name: "encode", state: .active)

        XCTAssertThrowsError(try failing.register(record))
        XCTAssertEqual(writes, 0)
    }

    func testRegistrationSurfacesWriteFailure() throws {
        let failing = StagingOwnershipRegistry(
            url: root.appendingPathComponent("write.json"),
            persist: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        XCTAssertThrowsError(try failing.register(try makeRecord(name: "write", state: .active)))
    }

    func testUnreadableDocumentIsNotTreatedAsMissing() throws {
        let failing = StagingOwnershipRegistry(
            url: root.appendingPathComponent("unreadable.json"),
            readData: { throw CocoaError(.fileReadNoPermission) }
        )

        XCTAssertThrowsError(try failing.register(try makeRecord(name: "unreadable", state: .active))) { error in
            guard case StagingOwnershipRegistryError.unreadable = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCorruptDocumentIsPreservedAndBlocksMutation() throws {
        let url = root.appendingPathComponent("corrupt.json")
        let corrupt = Data("not-json-private-content".utf8)
        try corrupt.write(to: url)
        let failing = StagingOwnershipRegistry(url: url)

        XCTAssertThrowsError(try failing.register(try makeRecord(name: "corrupt", state: .active))) { error in
            guard case StagingOwnershipRegistryError.malformed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testInterruptedPersistenceLeavesPreviouslyCommittedDocumentReadable() throws {
        let url = root.appendingPathComponent("interrupted.json")
        let first = try makeRecord(name: "committed", state: .active)
        let durable = StagingOwnershipRegistry(url: url)
        try durable.register(first)
        let original = try Data(contentsOf: url)
        let interrupted = StagingOwnershipRegistry(url: url, persist: { _ in throw CocoaError(.fileWriteUnknown) })

        XCTAssertThrowsError(try interrupted.setState(.completed, operationID: first.operationID))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try durable.records, [first])
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

import XCTest
@testable import PulseFiles

final class ArchiveAndBatchRenameTests: XCTestCase {
    func testStoredZipRoundTripAndConfiguredLimits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("hello.txt"); try Data("hello".utf8).write(to: source)
        let archive = root.appendingPathComponent("test.zip")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
        let service = ArchiveOperationService(accessPolicy: policy)
        let created = try await service.create(.init(sources: [source], destinationURL: archive))
        XCTAssertTrue(created.succeededCompletely)
        try FileManager.default.removeItem(at: source)
        let extracted = try await service.extract(.init(archiveURL: archive, destinationDirectory: root), conflictHandler: { _ in .cancel })
        XCTAssertTrue(extracted.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: source), "hello")

        await XCTAssertThrowsErrorAsync {
            _ = try await service.create(.init(sources: [source], destinationURL: root.appendingPathComponent("small.zip"), limits: .init(maximumItemCount: 10, maximumExpandedBytes: 1, maximumPathDepth: 10)))
        }
    }

    func testBatchRenamePreviewsAndExecutesCycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        let service = BatchRenameService(accessPolicy: .init(isEnabled: true, rootURL: root))
        let plan = try service.plan(.init(sources: [a, b], proposedNames: ["b", "a"]))
        XCTAssertEqual(plan.items.map(\.destinationURL), [b, a])
        let result = await service.execute(plan)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: a), "B")
        XCTAssertEqual(try String(contentsOf: b), "A")
    }

    private func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void) async {
        do { try await expression(); XCTFail("Expected an error") } catch { }
    }
}

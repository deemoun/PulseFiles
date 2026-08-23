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

    func testExtractionFailureRollsBackPublishedNonConflictingChild() async throws {
        let fixture = try await archiveFixture(names: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = ArchiveFailingFileManager()
        manager.failPublicationNamed = "b.txt"

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.service(fileManager: manager).extract(fixture.request, conflictHandler: { _ in .replace })
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("b.txt").path))
    }

    func testExtractionFailureRollsBackReplacementAndNewChild() async throws {
        let fixture = try await archiveFixture(names: ["a.txt", "b.txt", "c.txt"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let replaced = fixture.destination.appendingPathComponent("a.txt")
        try Data("original".utf8).write(to: replaced)
        let manager = ArchiveFailingFileManager()
        manager.failPublicationNamed = "c.txt"

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.service(fileManager: manager).extract(fixture.request, conflictHandler: { _ in .replace })
        }

        XCTAssertEqual(try String(contentsOf: replaced), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("b.txt").path))
    }

    func testExtractionCancellationDuringPublicationRollsBackOutputs() async throws {
        let fixture = try await archiveFixture(names: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = ArchiveFailingFileManager()
        var task: Task<FileOperationResult, Error>!
        manager.afterFirstPublication = { task.cancel() }
        task = Task {
            try await fixture.service(fileManager: manager).extract(fixture.request, conflictHandler: { _ in .replace })
        }

        let result = try await task.value
        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.completedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("a.txt").path))
    }

    func testExtractionRollbackFailureReturnsStructuredPartialResult() async throws {
        let fixture = try await archiveFixture(names: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = ArchiveFailingFileManager()
        manager.failPublicationNamed = "b.txt"
        manager.failRollbackNamed = "a.txt"

        let result = try await fixture.service(fileManager: manager).extract(fixture.request, conflictHandler: { _ in .replace })

        XCTAssertEqual(result.completedItems.map(\.lastPathComponent), ["a.txt"])
        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("a.txt").path))
    }

    func testExtractionRollbackPreservesUnrelatedDestinationItem() async throws {
        let fixture = try await archiveFixture(names: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = ArchiveFailingFileManager()
        manager.failPublicationNamed = "b.txt"
        manager.replaceBeforeRollbackNamed = "a.txt"

        let result = try await fixture.service(fileManager: manager).extract(fixture.request, conflictHandler: { _ in .replace })

        XCTAssertEqual(try String(contentsOf: fixture.destination.appendingPathComponent("a.txt")), "unrelated")
        XCTAssertTrue(result.completedItems.isEmpty)
        XCTAssertEqual(result.cleanupWarnings.count, 1)
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

    private func archiveFixture(names: [String]) async throws -> ArchiveFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceURLs = try names.map { name -> URL in
            let url = sources.appendingPathComponent(name)
            try Data("archive-\(name)".utf8).write(to: url)
            return url
        }
        let archive = root.appendingPathComponent("test.zip")
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
        _ = try await ArchiveOperationService(accessPolicy: policy).create(.init(sources: sourceURLs, destinationURL: archive))
        return ArchiveFixture(root: root, destination: destination, archive: archive, policy: policy)
    }
}

private struct ArchiveFixture {
    let root: URL
    let destination: URL
    let archive: URL
    let policy: SandboxFileAccessPolicy

    var request: ArchiveExtractRequest { .init(archiveURL: archive, destinationDirectory: destination) }
    func service(fileManager: FileManager) -> ArchiveOperationService {
        ArchiveOperationService(fileManager: fileManager, accessPolicy: policy)
    }
}

private final class ArchiveFailingFileManager: FileManager {
    var failPublicationNamed: String?
    var failRollbackNamed: String?
    var replaceBeforeRollbackNamed: String?
    var afterFirstPublication: (() -> Void)?
    private var publicationCount = 0
    private var publicationFailed = false
    private var replacedUnrelated = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        let isPublication = srcURL.path.contains(".pulsefiles-extract-") &&
            !srcURL.path.contains(".replacement-backups") &&
            dstURL.deletingLastPathComponent().lastPathComponent == "destination"
        if isPublication, dstURL.lastPathComponent == failPublicationNamed {
            publicationFailed = true
            throw CocoaError(.fileWriteNoPermission)
        }
        let isRollback = publicationFailed &&
            srcURL.deletingLastPathComponent().lastPathComponent == "destination" &&
            dstURL.path.contains(".pulsefiles-extract-")
        if isRollback, srcURL.lastPathComponent == failRollbackNamed {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
        if isPublication {
            publicationCount += 1
            if publicationCount == 1 { afterFirstPublication?() }
        }
    }

    override func fileExists(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if publicationFailed, !replacedUnrelated,
           url.deletingLastPathComponent().lastPathComponent == "destination",
           url.lastPathComponent == replaceBeforeRollbackNamed {
            replacedUnrelated = true
            try? super.removeItem(at: url)
            try? Data("unrelated".utf8).write(to: url)
        }
        return super.fileExists(atPath: path)
    }
}

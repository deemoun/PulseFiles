import Foundation
import XCTest
@testable import PulseFiles

final class ScratchFolderCleanupServiceTests: XCTestCase {
    func testEmptyFolderInventoryAndCleanupPreserveRoot() async throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupEmpty", testCase: self)
        let scratch = try fixture.folder("scratch")
        let operations = ScratchOperationSpy()
        let service = makeService(root: fixture.root, operations: operations)
        let inventory = try service.inventory(for: service.captureSelection(for: scratch))

        XCTAssertEqual(inventory.itemCount, 0)
        XCTAssertEqual(inventory.allocatedByteCount, 0)
        let result = try await service.cleanup(inventory, action: .moveToTrash)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.path))
        XCTAssertEqual(operations.trashCalls.count, 0)
    }

    func testNestedInventoryCountsAllContentsButDeletesOnlyTopLevelItems() async throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupNested", testCase: self)
        let scratch = try fixture.folder("scratch")
        _ = try fixture.file("scratch/folder/nested.txt", contents: "data")
        _ = try fixture.file("scratch/top.txt", contents: "more data")
        let operations = ScratchOperationSpy()
        let service = makeService(root: fixture.root, operations: operations)
        let inventory = try service.inventory(for: service.captureSelection(for: scratch))

        XCTAssertEqual(inventory.itemCount, 3)
        XCTAssertEqual(Set(inventory.deletionURLs.map(\.lastPathComponent)), ["folder", "top.txt"])
        _ = try await service.cleanup(inventory, action: .permanentlyDelete)
        XCTAssertEqual(operations.deleteCalls.single?.count, 2)
        XCTAssertFalse(operations.deleteCalls.single?.contains(scratch) ?? true)
    }

    func testConfiguredSymlinkIsRejected() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupSymlink", testCase: self)
        let target = try fixture.folder("target")
        let link = fixture.path("scratch-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let service = makeService(root: fixture.root)
        XCTAssertThrowsError(try service.captureSelection(for: link)) { error in
            XCTAssertEqual(error as? ScratchFolderCleanupError, .symbolicLink(link.standardizedFileURL))
        }
    }

    func testInaccessibleFolderIsRejected() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupInaccessible", testCase: self)
        let scratch = try fixture.folder("scratch")
        let policy = SandboxFileAccessPolicy(
            isEnabled: false,
            rootURL: fixture.root,
            accessProbe: .init(fileExists: { _ in true }, isReadableFile: { _ in false }, isWritableFile: { _ in false })
        )
        let service = ScratchFolderCleanupService(accessPolicy: policy, fileOperations: ScratchOperationSpy(), identity: { $0.path })
        XCTAssertThrowsError(try service.captureSelection(for: scratch))
    }

    func testUnsafeRootsAndActivePaneRootAreRejected() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupUnsafe", testCase: self)
        let scratch = try fixture.folder("scratch")
        let service = makeService(root: fixture.root, activeRoots: [scratch])
        XCTAssertThrowsError(try service.captureSelection(for: scratch)) { error in
            XCTAssertEqual(error as? ScratchFolderCleanupError, .unsafeLocation(scratch.standardizedFileURL))
        }
        XCTAssertThrowsError(try service.captureSelection(for: URL(fileURLWithPath: "/", isDirectory: true)))
        XCTAssertThrowsError(try service.captureSelection(for: FileManager.default.homeDirectoryForCurrentUser))
    }

    func testCancellationDoesNotInvokeFileOperations() async throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupCancel", testCase: self)
        let scratch = try fixture.folder("scratch")
        _ = try fixture.file("scratch/keep.txt")
        let operations = ScratchOperationSpy()
        let service = makeService(root: fixture.root, operations: operations)
        let inventory = try service.inventory(for: service.captureSelection(for: scratch))
        let result = try await service.cleanup(inventory, action: nil)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(operations.trashCalls.isEmpty)
        XCTAssertTrue(operations.deleteCalls.isEmpty)
    }

    func testPartialFailureIsReturnedUnchanged() async throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupPartial", testCase: self)
        let scratch = try fixture.folder("scratch")
        let first = try fixture.file("scratch/first.txt")
        let second = try fixture.file("scratch/second.txt")
        let failure = CocoaError(.fileWriteNoPermission)
        let operations = ScratchOperationSpy(result: .init(completedItems: [first], skippedItems: [], failedItems: [.init(url: second, error: failure)], wasCancelled: false))
        let service = makeService(root: fixture.root, operations: operations)
        let result = try await service.cleanup(try service.inventory(for: service.captureSelection(for: scratch)), action: .moveToTrash)
        XCTAssertEqual(result.completedItems, [first])
        XCTAssertEqual(result.failedItems.map(\.url), [second])
    }

    func testReplacementAfterInventoryAbortsBeforeMutation() throws {
        let fixture = try TemporaryDirectoryFixture(named: "ScratchCleanupReplacement", testCase: self)
        let scratch = try fixture.folder("scratch")
        let service = makeService(root: fixture.root)
        let selection = try service.captureSelection(for: scratch)
        try FileManager.default.removeItem(at: scratch)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        XCTAssertThrowsError(try service.inventory(for: selection)) { error in
            XCTAssertEqual(error as? ScratchFolderCleanupError, .uncertainTarget(scratch.standardizedFileURL))
        }
    }

    private func makeService(root: URL, operations: ScratchOperationSpy = ScratchOperationSpy(), activeRoots: [URL] = []) -> ScratchFolderCleanupService {
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: root)
        return ScratchFolderCleanupService(accessPolicy: policy, fileOperations: operations, activePaneRoots: { activeRoots })
    }
}

private final class ScratchOperationSpy: FileOperationServicing, @unchecked Sendable {
    var trashCalls: [[URL]] = []
    var deleteCalls: [[URL]] = []
    let result: FileOperationResult?
    init(result: FileOperationResult? = nil) { self.result = result }
    func trash(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { trashCalls.append(urls); return result ?? success(urls) }
    func delete(_ urls: [URL], progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { deleteCalls.append(urls); return result ?? success(urls) }
    private func success(_ urls: [URL]) -> FileOperationResult { .init(completedItems: urls, skippedItems: [], failedItems: [], wasCancelled: false) }
    func transferCapacityPreflight(for request: FileOperationRequest, isMove: Bool) async throws -> FileTransferCapacityPreflight { .notRequired }
    func copy(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func move(_ request: FileOperationRequest, conflictHandler: @escaping FileConflictHandler, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func rename(_ source: URL, to rawName: String, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func undo(_ recovery: FileOperationRecovery, progressHandler: FileOperationProgressHandler?) async throws -> FileOperationResult { fatalError() }
    func createFolder(named rawName: String, in directory: URL) async throws -> FileOperationResult { fatalError() }
    func createFile(named rawName: String, in directory: URL) async throws -> FileOperationResult { fatalError() }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

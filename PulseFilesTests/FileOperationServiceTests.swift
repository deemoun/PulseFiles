import XCTest
@testable import PulseFiles

final class FileOperationServiceTests: XCTestCase {
    func testCopyWithoutConflictCreatesDestinationAndKeepsSource() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Report.txt")), "source")
    }

    func testCopyReplaceStagesBeforeReplacingDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: destination), "new")
    }

    func testCopySkipLeavesDestinationUntouched() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .skip },
            progressHandler: nil
        )

        XCTAssertFalse(result.succeededCompletely)
        XCTAssertEqual(result.skippedItems, [source])
        XCTAssertEqual(try String(contentsOf: destination), "old")
    }

    func testCopyCancelLeavesAllItemsUntouchedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: destination), "old")
    }

    func testMoveWithoutConflictUsesDirectMove() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(fixture.failingFileManager?.movedItems, [RecordedFileOperation(source: source, destination: destination)])
        XCTAssertEqual(fixture.failingFileManager?.copiedItems, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination), "source")
    }

    func testMoveWithoutConflictFallsBackToCopyDeleteForCrossVolumeMoveFailure() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failMoveToURL = destination
        fixture.failingFileManager?.moveFailureError = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EXDEV.rawValue))

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(fixture.failingFileManager?.copiedItems.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination), "source")
    }

    func testFolderIntoItselfIsRejectedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        do {
            _ = try await fixture.service.copy(
                FileOperationRequest(sources: [folder], destinationDirectory: child),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected folder-into-itself rejection")
        } catch FileOperationError.destinationInsideSource {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDuplicateSourcesAreRejectedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.copy(
                FileOperationRequest(sources: [source, source], destinationDirectory: fixture.right),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected duplicate source rejection")
        } catch FileOperationError.duplicateSource {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingDestinationDirectoryIsRejectedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let missingDestination = fixture.root.appendingPathComponent("Missing", isDirectory: true)
        try "source".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.copy(
                FileOperationRequest(sources: [source], destinationDirectory: missingDestination),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected missing destination rejection")
        } catch FileOperationError.destinationDirectoryMissing {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSandboxRejectsOutsideSourceBeforeMutation() async throws {
        let fixture = try makeFixture()
        let outside = try makeTemporaryDirectory().appendingPathComponent("Outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.copy(
                FileOperationRequest(sources: [outside], destinationDirectory: fixture.right),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected sandbox rejection")
        } catch SandboxAccessError.outsideExperimentalSandbox {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReplaceFailureRestoresOriginalDestination() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failMoveToURL = destination

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertEqual(try String(contentsOf: destination), "old")
        XCTAssertEqual(try String(contentsOf: source), "new")
    }

    func testBackupCleanupFailureIsReportedWithoutFailingReplacement() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failBackupRemoval = true

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertEqual(result.completedItems, [source])
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertEqual(try String(contentsOf: destination), "new")
    }

    func testMoveReplaceStagesDestinationAndRemovesOriginal() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(fixture.failingFileManager?.copiedItems.count, 1)
        XCTAssertTrue(fixture.failingFileManager?.movedItems.contains { $0.destination.lastPathComponent.hasPrefix(".pulsefiles-backup") } == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination), "new")
    }

    func testMoveReportsWarningWhenOriginalCannotBeRemovedAfterFallbackCopy() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failMoveToURL = destination
        fixture.failingFileManager?.moveFailureError = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EXDEV.rawValue))
        fixture.failingFileManager?.failRemoveURL = source

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertEqual(result.completedItems, [source])
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertEqual(try String(contentsOf: source), "source")
        XCTAssertEqual(try String(contentsOf: destination), "source")
    }

    func testPermanentDeleteRejectsDuplicateSourcesBeforeMutation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.delete([source, source], progressHandler: nil)
            XCTFail("Expected duplicate delete rejection")
        } catch FileOperationError.duplicateSource {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try String(contentsOf: source), "source")
    }

    func testRenameUsesNoOverwriteValidation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Old.txt")
        let destination = fixture.left.appendingPathComponent("New.txt")
        try "old".write(to: source, atomically: true, encoding: .utf8)

        let result = try await fixture.service.rename(source, to: "New.txt", progressHandler: nil)

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination), "old")
    }

    func testRenameRejectsDuplicateName() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Old.txt")
        let destination = fixture.left.appendingPathComponent("New.txt")
        try "old".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: destination, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.rename(source, to: "New.txt", progressHandler: nil)
            XCTFail("Expected duplicate rename rejection")
        } catch FileNameValidator.ValidationError.duplicateName {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenameRejectsInvalidName() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Old.txt")
        try "old".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.rename(source, to: "../Bad.txt", progressHandler: nil)
            XCTFail("Expected invalid name rejection")
        } catch FileNameValidator.ValidationError.containsSlash {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenameRejectsOutsideSandbox() async throws {
        let fixture = try makeFixture()
        let outsideDirectory = try makeTemporaryDirectory()
        let outside = outsideDirectory.appendingPathComponent("Outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.rename(outside, to: "Other.txt", progressHandler: nil)
            XCTFail("Expected sandbox rejection")
        } catch SandboxAccessError.outsideExperimentalSandbox {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private struct Fixture {
        let root: URL
        let left: URL
        let right: URL
        let service: FileOperationService
        let failingFileManager: FailingFileManager?
    }

    private func makeFixture(useFailingManager: Bool = false) throws -> Fixture {
        let sandbox = try SandboxFixture(testCase: self)
        let left = try sandbox.temporaryDirectory.folder("AllowedSandbox/Left")
        let right = try sandbox.temporaryDirectory.folder("AllowedSandbox/Right")
        if useFailingManager {
            let failingFileManager = FailingFileManager()
            return Fixture(root: sandbox.root, left: left, right: right, service: FileOperationService(fileManager: failingFileManager, accessPolicy: sandbox.policy), failingFileManager: failingFileManager)
        }
        return Fixture(root: sandbox.root, left: left, right: right, service: sandbox.fileOperationService(), failingFileManager: nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TemporaryDirectoryFixture(testCase: self).root
    }
}

private struct RecordedFileOperation: Equatable {
    let source: URL
    let destination: URL
}

private final class FailingFileManager: FileOperationFileManaging {
    var failMoveToURL: URL?
    var moveFailureError: Error = CocoaError(.fileWriteUnknown)
    var failRemoveURL: URL?
    var failBackupRemoval = false
    private(set) var copiedItems: [RecordedFileOperation] = []
    private(set) var movedItems: [RecordedFileOperation] = []

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copiedItems.append(RecordedFileOperation(source: srcURL, destination: dstURL))
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let failMoveToURL, dstURL.standardizedFileURL == failMoveToURL.standardizedFileURL {
            throw moveFailureError
        }
        movedItems.append(RecordedFileOperation(source: srcURL, destination: dstURL))
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    func removeItem(at URL: URL) throws {
        if let failRemoveURL, URL.standardizedFileURL == failRemoveURL.standardizedFileURL {
            throw CocoaError(.fileWriteNoPermission)
        }
        if failBackupRemoval, URL.lastPathComponent.hasPrefix(".pulsefiles-backup") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: URL)
    }

    func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        outResultingURL?.pointee = resultingURL
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}

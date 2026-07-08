import XCTest
@testable import PulseFiles

final class FileOperationServiceTests: XCTestCase {
    func testDropTransferPolicyDefaultsInternalSameVolumeDragToMove() throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let policy = DropTransferPolicy(volumeIdentifierProvider: { url in
            url.path.hasPrefix(fixture.root.path) ? "sandbox-volume" : nil
        })

        let operation = policy.resolvedOperation(
            for: [source],
            destinationDirectory: fixture.right,
            isInternalAppDrag: true,
            optionForcesCopy: false
        )

        XCTAssertEqual(operation, .move)
    }

    func testDropTransferPolicyDefaultsExternalDragToCopy() throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let policy = DropTransferPolicy(volumeIdentifierProvider: { _ in "same-volume" })

        let operation = policy.resolvedOperation(
            for: [source],
            destinationDirectory: fixture.right,
            isInternalAppDrag: false,
            optionForcesCopy: false
        )

        XCTAssertEqual(operation, .copy)
    }

    func testDropTransferPolicyDefaultsCrossVolumeDragToCopy() throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let policy = DropTransferPolicy(volumeIdentifierProvider: { url in
            url.path.hasPrefix(fixture.left.path) ? "left-volume" : "right-volume"
        })

        let operation = policy.resolvedOperation(
            for: [source],
            destinationDirectory: fixture.right,
            isInternalAppDrag: true,
            optionForcesCopy: false
        )

        XCTAssertEqual(operation, .copy)
    }

    func testDropTransferPolicyOptionForcesCopyForInternalSameVolumeDrag() throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let policy = DropTransferPolicy(volumeIdentifierProvider: { _ in "same-volume" })

        let operation = policy.resolvedOperation(
            for: [source],
            destinationDirectory: fixture.right,
            isInternalAppDrag: true,
            optionForcesCopy: true
        )

        XCTAssertEqual(operation, .copy)
    }


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


    func testCopyRetriesWhenGeneratedStagingPathAlreadyExists() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.simulateFirstGeneratedStagingPathExists(prefix: ".pulsefiles-copy", destinationLastPathComponent: destination.lastPathComponent)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(fixture.failingFileManager?.copiedItems.count, 1)
        XCTAssertEqual(fixture.failingFileManager?.simulatedExistingStagingPathHits, 1)
        XCTAssertEqual(try String(contentsOf: destination), "source")
        XCTAssertFalse(fixture.failingFileManager?.copiedItems.first?.destination.lastPathComponent == fixture.failingFileManager?.simulatedExistingStagingLastPathComponent)
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
        } catch FileOperationError.destinationInsideSource(let rejectedSource, let rejectedDestination) {
            let error = FileOperationError.destinationInsideSource(source: rejectedSource, destination: rejectedDestination)
            XCTAssertEqual(error.errorDescription, "Cannot copy or move a folder into itself.")
            XCTAssertEqual(error.localizedDescription, "Cannot copy or move a folder into itself.")
            XCTAssertEqual(error.failureReason, "Cannot copy or move Folder into \(child.appendingPathComponent("Folder").path).")
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

    func testMoveConflictWithSkipLeavesSourceAndDestinationUntouched() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .skip },
            progressHandler: nil
        )

        XCTAssertFalse(result.succeededCompletely)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.completedItems, [])
        XCTAssertEqual(result.skippedItems, [source])
        XCTAssertEqual(result.failedItems.count, 0)
        XCTAssertEqual(result.cleanupWarnings.count, 0)
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: destination), "old")
    }

    func testMoveConflictWithCancelLeavesSourceAndDestinationUntouched() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertFalse(result.succeededCompletely)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.completedItems, [])
        XCTAssertEqual(result.skippedItems, [])
        XCTAssertEqual(result.failedItems.count, 0)
        XCTAssertEqual(result.cleanupWarnings.count, 0)
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: destination), "old")
    }

    func testDuplicateDestinationsAreRejectedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let firstFolder = fixture.left.appendingPathComponent("First", isDirectory: true)
        let secondFolder = fixture.left.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstSource = firstFolder.appendingPathComponent("Report.txt")
        let secondSource = secondFolder.appendingPathComponent("Report.txt")
        try "first".write(to: firstSource, atomically: true, encoding: .utf8)
        try "second".write(to: secondSource, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.copy(
                FileOperationRequest(sources: [firstSource, secondSource], destinationDirectory: fixture.right),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected duplicate destination rejection")
        } catch FileOperationError.duplicateDestination(let duplicateURL) {
            XCTAssertEqual(duplicateURL, fixture.right.appendingPathComponent("Report.txt"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Report.txt").path))
        XCTAssertEqual(try String(contentsOf: firstSource), "first")
        XCTAssertEqual(try String(contentsOf: secondSource), "second")
    }

    func testMoveFolderIntoItselfIsRejectedBeforeMutation() async throws {
        let fixture = try makeFixture()
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        let nestedFile = child.appendingPathComponent("Nested.txt")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "nested".write(to: nestedFile, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.move(
                FileOperationRequest(sources: [folder], destinationDirectory: child),
                conflictHandler: { _ in .replace },
                progressHandler: nil
            )
            XCTFail("Expected folder-into-itself rejection")
        } catch FileOperationError.destinationInsideSource(let rejectedSource, let rejectedDestination) {
            XCTAssertEqual(rejectedSource, folder)
            XCTAssertEqual(rejectedDestination, child.appendingPathComponent("Folder"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try String(contentsOf: nestedFile), "nested")
    }

    func testCopyReportsPartialFailureWhenOneItemSucceedsAndAnotherFails() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let firstSource = fixture.left.appendingPathComponent("First.txt")
        let secondSource = fixture.left.appendingPathComponent("Second.txt")
        try "first".write(to: firstSource, atomically: true, encoding: .utf8)
        try "second".write(to: secondSource, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failCopyFromURL = secondSource

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [firstSource, secondSource], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: nil
        )

        XCTAssertFalse(result.succeededCompletely)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.completedItems, [firstSource])
        XCTAssertEqual(result.skippedItems, [])
        XCTAssertEqual(result.failedItems.map(\.url), [secondSource])
        XCTAssertEqual(result.cleanupWarnings.count, 0)
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("First.txt")), "first")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Second.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSource.path))
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


    func testCopyNestedDirectoryReportsRecursiveItemProgress() async throws {
        let fixture = try makeFixture()
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "root".write(to: folder.appendingPathComponent("Root.txt"), atomically: true, encoding: .utf8)
        try "nested".write(to: child.appendingPathComponent("Nested.txt"), atomically: true, encoding: .utf8)
        var progressEvents: [FileOperationProgress] = []

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [folder], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { progressEvents.append($0) }
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Folder/Child/Nested.txt")), "nested")
        XCTAssertEqual(progressEvents.compactMap(\.totalRecursiveItemCount).last, 4)
        XCTAssertEqual(progressEvents.compactMap(\.completedRecursiveItemCount).max(), 4)
        XCTAssertTrue(progressEvents.contains { $0.currentItemName == "Nested.txt" && $0.completedRecursiveItemCount == 4 })
    }

    func testFallbackMoveNestedDirectoryReportsRecursiveItemProgress() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        let destination = fixture.right.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "nested".write(to: child.appendingPathComponent("Nested.txt"), atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failMoveToURL = destination
        fixture.failingFileManager?.moveFailureError = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EXDEV.rawValue))
        var progressEvents: [FileOperationProgress] = []

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [folder], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { progressEvents.append($0) }
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Child/Nested.txt")), "nested")
        XCTAssertEqual(progressEvents.compactMap(\.totalRecursiveItemCount).last, 3)
        XCTAssertEqual(progressEvents.compactMap(\.completedRecursiveItemCount).max(), 3)
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
    var failCopyFromURL: URL?
    var failMoveToURL: URL?
    var moveFailureError: Error = CocoaError(.fileWriteUnknown)
    var failRemoveURL: URL?
    var failBackupRemoval = false
    private var simulatedExistingStagingPrefix: String?
    private var simulatedExistingStagingDestinationLastPathComponent: String?
    private(set) var simulatedExistingStagingLastPathComponent: String?
    private(set) var simulatedExistingStagingPathHits = 0
    private(set) var copiedItems: [RecordedFileOperation] = []
    private(set) var movedItems: [RecordedFileOperation] = []

    func fileExists(atPath path: String) -> Bool {
        if shouldSimulateExistingGeneratedStagingPath(path) {
            simulatedExistingStagingPathHits += 1
            simulatedExistingStagingLastPathComponent = URL(fileURLWithPath: path).lastPathComponent
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func simulateFirstGeneratedStagingPathExists(prefix: String, destinationLastPathComponent: String) {
        simulatedExistingStagingPrefix = prefix
        simulatedExistingStagingDestinationLastPathComponent = destinationLastPathComponent
    }

    private func shouldSimulateExistingGeneratedStagingPath(_ path: String) -> Bool {
        guard simulatedExistingStagingPathHits == 0,
              let prefix = simulatedExistingStagingPrefix,
              let destinationLastPathComponent = simulatedExistingStagingDestinationLastPathComponent else {
            return false
        }

        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastPathComponent.hasPrefix("\(prefix)-") && lastPathComponent.hasSuffix("-\(destinationLastPathComponent)")
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if let failCopyFromURL, srcURL.standardizedFileURL == failCopyFromURL.standardizedFileURL {
            throw CocoaError(.fileReadNoPermission)
        }
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

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
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

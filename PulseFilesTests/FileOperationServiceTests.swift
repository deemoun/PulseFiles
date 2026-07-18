import XCTest
#if os(macOS)
import Darwin
#endif
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

    func testStagedCopyPreservesFileAndDirectoryMetadata() async throws {
        #if os(macOS)
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Metadata", isDirectory: true)
        let child = source.appendingPathComponent("Document.txt")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "metadata".write(to: child, atomically: true, encoding: .utf8)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: timestamp], ofItemAtPath: child.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o750, .modificationDate: timestamp], ofItemAtPath: source.path)
        try setTestExtendedAttribute(on: child)

        let result = try await fixture.service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let copiedDirectory = fixture.right.appendingPathComponent("Metadata")
        let copiedChild = copiedDirectory.appendingPathComponent("Document.txt")

        XCTAssertTrue(result.cleanupWarnings.isEmpty, "Metadata preservation warnings: \(result.cleanupWarnings.map(\.message))")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copiedChild.path)[.posixPermissions] as? NSNumber, 0o640)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copiedDirectory.path)[.posixPermissions] as? NSNumber, 0o750)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copiedDirectory.path)[.modificationDate] as? Date, timestamp)
        XCTAssertEqual(try testExtendedAttribute(on: copiedChild), Data("pulsefiles".utf8))
        #else
        throw XCTSkip("macOS metadata APIs are unavailable on this platform.")
        #endif
    }

    func testCrossVolumeFallbackMovePreservesMetadata() async throws {
        #if os(macOS)
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Metadata.txt")
        try "metadata".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        try setTestExtendedAttribute(on: source)
        fixture.failingFileManager?.failMoveToURL = fixture.right.appendingPathComponent(source.lastPathComponent)
        fixture.failingFileManager?.moveFailureError = POSIXError(.EXDEV)

        let result = try await fixture.service.move(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let destination = fixture.right.appendingPathComponent(source.lastPathComponent)

        XCTAssertTrue(result.cleanupWarnings.isEmpty, "Metadata preservation warnings: \(result.cleanupWarnings.map(\.message))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber, 0o600)
        XCTAssertEqual(try testExtendedAttribute(on: destination), Data("pulsefiles".utf8))
        #else
        throw XCTSkip("macOS metadata APIs are unavailable on this platform.")
        #endif
    }

    func testCopySymbolicLinkToFilePreservesLinkWithoutCopyingTarget() async throws {
        let fixture = try makeFixture()
        let target = fixture.left.appendingPathComponent("Target.txt")
        let link = fixture.left.appendingPathComponent("Target Link.txt")
        try "target contents".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [link], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel }, progressHandler: nil
        )

        let copiedLink = fixture.right.appendingPathComponent(link.lastPathComponent)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path), target.path)
        XCTAssertEqual(try copiedLink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    }

    func testCopyDirectorySymbolicLinkOutsideSourceRootPreservesLinkWithoutReadingOutsideContent() async throws {
        let fixture = try makeFixture()
        let outsideDirectory = try makeTemporaryDirectory()
        let outsideFile = outsideDirectory.appendingPathComponent("Private.txt")
        let link = fixture.left.appendingPathComponent("External Directory")
        try "outside content".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideDirectory)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [link], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel }, progressHandler: nil
        )

        let copiedLink = fixture.right.appendingPathComponent(link.lastPathComponent)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path), outsideDirectory.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: fixture.right, includingPropertiesForKeys: nil).map(\.lastPathComponent), [link.lastPathComponent])
    }

    func testCopyCyclicDirectorySymbolicLinkTerminatesByPreservingLink() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cycle", isDirectory: true)
        let link = source.appendingPathComponent("Self")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel }, progressHandler: nil
        )

        let copiedLink = fixture.right.appendingPathComponent("Cycle/Self")
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path), source.path)
        XCTAssertEqual(try copiedLink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
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
        XCTAssertEqual(fixture.failingFileManager?.simulatedExistingStagingPathHits, 1)
        XCTAssertEqual(try String(contentsOf: destination), "source")
    }

    func testCopyKeepBothCreatesUniqueGeneratedDestinationName() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .keepBoth },
            progressHandler: nil
        )

        let keptBothDestination = fixture.right.appendingPathComponent("Report copy.txt")
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: destination), "old")
        XCTAssertEqual(try String(contentsOf: keptBothDestination), "new")
    }

    func testCopyKeepBothRetriesGeneratedNameCollisions() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: fixture.right.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        try "first copy".write(to: fixture.right.appendingPathComponent("Report copy.txt"), atomically: true, encoding: .utf8)
        try "second copy".write(to: fixture.right.appendingPathComponent("Report copy 2.txt"), atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .keepBoth },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Report copy 3.txt")), "new")
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Report copy.txt")), "first copy")
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Report copy 2.txt")), "second copy")
    }

    func testCopyApplyKeepBothToRemainingConflictsUsesOneConflictDecision() async throws {
        let fixture = try makeFixture()
        let firstSource = fixture.left.appendingPathComponent("One.txt")
        let secondSource = fixture.left.appendingPathComponent("Two.txt")
        try "new one".write(to: firstSource, atomically: true, encoding: .utf8)
        try "new two".write(to: secondSource, atomically: true, encoding: .utf8)
        try "old one".write(to: fixture.right.appendingPathComponent("One.txt"), atomically: true, encoding: .utf8)
        try "old two".write(to: fixture.right.appendingPathComponent("Two.txt"), atomically: true, encoding: .utf8)
        var conflictPromptCount = 0

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [firstSource, secondSource], destinationDirectory: fixture.right),
            conflictHandler: { _ in
                conflictPromptCount += 1
                return .applyToRemainingKeepBoth
            },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(conflictPromptCount, 1)
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("One.txt")), "old one")
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Two.txt")), "old two")
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("One copy.txt")), "new one")
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Two copy.txt")), "new two")
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
        let service = FileOperationService(
            fileManager: fixture.failingFileManager!,
            accessPolicy: fixture.unrestrictedPolicy,
            streamingCopier: FailingStreamingCopier(failingSource: secondSource)
        )

        let result = try await service.copy(
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

    func testCopyFailureRetainsTemporaryCleanupWarning() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failStagingRemoval = true
        let service = FileOperationService(
            fileManager: fixture.failingFileManager!,
            accessPolicy: fixture.unrestrictedPolicy,
            streamingCopier: PartialFailureStreamingCopier(error: CocoaError(.fileWriteNoPermission))
        )

        let result = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)

        XCTAssertEqual(result.failedItems.map(\.url), [source])
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertTrue(result.cleanupWarnings[0].url.lastPathComponent.hasPrefix(".pulsefiles-copy"))
        XCTAssertTrue(result.cleanupWarnings[0].message.contains(result.cleanupWarnings[0].url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Report.txt").path))
    }

    func testFallbackMoveFailureRetainsTemporaryCleanupWarning() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        let destination = fixture.right.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failMoveToURL = destination
        fixture.failingFileManager?.moveFailureError = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EXDEV.rawValue))
        fixture.failingFileManager?.failStagingRemoval = true
        let service = FileOperationService(fileManager: fixture.failingFileManager!, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: PartialFailureStreamingCopier(error: CocoaError(.fileWriteNoPermission)))

        let result = try await service.move(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)

        XCTAssertEqual(result.failedItems.map(\.url), [source])
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertTrue(result.cleanupWarnings[0].url.lastPathComponent.hasPrefix(".pulsefiles-move"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancelledCopyRetainsTemporaryCleanupWarningWithoutMarkingDestinationComplete() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failStagingRemoval = true
        let service = FileOperationService(fileManager: fixture.failingFileManager!, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: PartialFailureStreamingCopier(error: CancellationError()))

        let result = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.completedItems.isEmpty)
        XCTAssertTrue(result.failedItems.isEmpty)
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Report.txt").path))
    }

    func testUnavailableVolumeFailureRetainsTemporaryCleanupWarningAndStopsTransfer() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let unavailableSource = fixture.left.appendingPathComponent("Unavailable.txt")
        let laterSource = fixture.left.appendingPathComponent("Later.txt")
        try "unavailable".write(to: unavailableSource, atomically: true, encoding: .utf8)
        try "later".write(to: laterSource, atomically: true, encoding: .utf8)
        fixture.failingFileManager?.failStagingRemoval = true
        let unavailableVolumeError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        let service = FileOperationService(fileManager: fixture.failingFileManager!, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: PartialFailureStreamingCopier(error: unavailableVolumeError))

        let result = try await service.copy(FileOperationRequest(sources: [unavailableSource, laterSource], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)

        XCTAssertEqual(result.failedItems.map(\.url), [unavailableSource])
        XCTAssertEqual(result.cleanupWarnings.count, 1)
        XCTAssertTrue(result.completedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Unavailable.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Later.txt").path))
    }

    @MainActor
    func testOperationResultPresentationDisplaysCleanupWarnings() {
        let temporaryURL = URL(fileURLWithPath: "/tmp/.pulsefiles-copy-report")
        let result = FileOperationResult(
            completedItems: [],
            skippedItems: [],
            failedItems: [FileOperationItemFailure(url: URL(fileURLWithPath: "/tmp/Report.txt"), error: CocoaError(.fileWriteNoPermission))],
            cleanupWarnings: [FileOperationCleanupWarning(url: temporaryURL, message: "Remove the temporary item manually.")],
            wasCancelled: false
        )

        let presentation = MainWindowViewController.operationResultPresentation(result, operationName: "Copy")

        XCTAssertEqual(presentation?.message, "Copy Finished With Issues")
        XCTAssertTrue(presentation?.detail.contains("Cleanup warnings: 1") == true)
        XCTAssertTrue(presentation?.detail.contains(".pulsefiles-copy-report: Remove the temporary item manually.") == true)
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
        XCTAssertEqual(progressEvents.compactMap(\.totalByteCount).last, 10)
        XCTAssertEqual(progressEvents.compactMap(\.completedByteCount).max(), 10)
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
        XCTAssertEqual(progressEvents.compactMap(\.totalByteCount).last, 6)
        XCTAssertEqual(progressEvents.compactMap(\.completedByteCount).max(), 6)
    }

    func testStreamingCopyReportsMonotonicAggregateByteProgressForNestedAndEmptyFiles() async throws {
        let fixture = try makeFixture()
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 6).write(to: folder.appendingPathComponent("Data.bin"))
        FileManager.default.createFile(atPath: folder.appendingPathComponent("Empty.bin").path, contents: Data())
        let copier = ScriptedStreamingCopier(chunkSize: 2)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)
        var progressEvents: [FileOperationProgress] = []

        let result = try await service.copy(
            FileOperationRequest(sources: [folder], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { progressEvents.append($0) }
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(progressEvents.compactMap(\.totalByteCount).last, 6)
        XCTAssertEqual(progressEvents.compactMap(\.completedByteCount).max(), 6)
        XCTAssertEqual(progressEvents.compactMap(\.completedByteCount), progressEvents.compactMap(\.completedByteCount).sorted())
        XCTAssertEqual(try Data(contentsOf: fixture.right.appendingPathComponent("Folder/Data.bin")).count, 6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Folder/Empty.bin").path))
    }

    func testStreamingCopyCancellationLeavesNoStagedDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Data.bin")
        try Data(repeating: 1, count: 4).write(to: source)
        let copier = ScriptedStreamingCopier(chunkSize: 2, cancelsAfterFirstChunk: true)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)

        let result = try await service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { _ in }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Data.bin").path))
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

    func testCopyRejectsParentAndChildSourcesBeforeConflictResolutionOrMutation() async throws {
        try await assertOverlappingSelectionIsRejected { service, parent, child, destination in
            try await service.copy(
                FileOperationRequest(sources: [parent, child], destinationDirectory: destination),
                conflictHandler: { _ in
                    XCTFail("Conflict resolution must not run for overlapping sources")
                    return .replace
                },
                progressHandler: nil
            )
        }
    }

    func testMoveRejectsParentAndChildSourcesBeforeConflictResolutionOrMutation() async throws {
        try await assertOverlappingSelectionIsRejected { service, parent, child, destination in
            try await service.move(
                FileOperationRequest(sources: [parent, child], destinationDirectory: destination),
                conflictHandler: { _ in
                    XCTFail("Conflict resolution must not run for overlapping sources")
                    return .replace
                },
                progressHandler: nil
            )
        }
    }

    func testTrashRejectsParentAndChildSourcesBeforeMutation() async throws {
        try await assertOverlappingSelectionIsRejected { service, parent, child, _ in
            try await service.trash([parent, child], progressHandler: nil)
        }
    }

    func testPermanentDeleteRejectsParentAndChildSourcesBeforeMutation() async throws {
        try await assertOverlappingSelectionIsRejected { service, parent, child, _ in
            try await service.delete([parent, child], progressHandler: nil)
        }
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


    func testCreateFileAllowsNonexistentDestinationWhenParentIsAccessibleInSandbox() throws {
        let fixture = try makeFixture()
        let destination = fixture.left.appendingPathComponent("Brand New.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let created = try fixture.service.createFile(named: "Brand New.txt", in: fixture.left)

        XCTAssertEqual(created, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCopyAllowsNonexistentDestinationWhenParentIsAccessibleInSandbox() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("New Copy Source.txt")
        let destination = fixture.right.appendingPathComponent(source.lastPathComponent)
        try "copy me".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: destination), "copy me")
    }

    func testMoveAllowsNonexistentDestinationWhenParentIsAccessibleInSandbox() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("New Move Source.txt")
        let destination = fixture.right.appendingPathComponent(source.lastPathComponent)
        try "move me".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let result = try await fixture.service.move(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination), "move me")
    }

    func testUnrestrictedModeAllowsCreationWhenNonexistentDestinationParentIsWritable() throws {
        let fixture = try makeFixture()
        let externalDirectory = try makeTemporaryDirectory()
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy)
        let destination = externalDirectory.appendingPathComponent("External New.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let created = try service.createFile(named: "External New.txt", in: externalDirectory)

        XCTAssertEqual(created, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCreateFolderCreatesDirectoryInSandbox() throws {
        let fixture = try makeFixture()

        let created = try fixture.service.createFolder(named: "New Folder", in: fixture.left)

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(created, fixture.left.appendingPathComponent("New Folder", isDirectory: true))
    }

    func testCreateFileCreatesEmptyFileInSandbox() throws {
        let fixture = try makeFixture()

        let created = try fixture.service.createFile(named: "Notes.txt", in: fixture.left)

        var isDirectory = ObjCBool(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertEqual(try Data(contentsOf: created), Data())
    }

    func testCreateFolderRejectsDuplicateName() throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.left.appendingPathComponent("Existing"), withIntermediateDirectories: false)

        do {
            _ = try fixture.service.createFolder(named: "Existing", in: fixture.left)
            XCTFail("Expected duplicate creation rejection")
        } catch FileNameValidator.ValidationError.duplicateName {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsDuplicateName() throws {
        let fixture = try makeFixture()
        let existing = fixture.left.appendingPathComponent("Existing.txt")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)

        do {
            _ = try fixture.service.createFile(named: "Existing.txt", in: fixture.left)
            XCTFail("Expected duplicate creation rejection")
        } catch FileNameValidator.ValidationError.duplicateName {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsInvalidName() throws {
        let fixture = try makeFixture()

        do {
            _ = try fixture.service.createFile(named: "../Bad.txt", in: fixture.left)
            XCTFail("Expected invalid name rejection")
        } catch FileNameValidator.ValidationError.containsSlash {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFolderRejectsMissingDestinationDirectory() throws {
        let fixture = try makeFixture()
        let missingDirectory = fixture.left.appendingPathComponent("Missing")

        do {
            _ = try fixture.service.createFolder(named: "New Folder", in: missingDirectory)
            XCTFail("Expected missing destination directory rejection")
        } catch FileOperationError.destinationDirectoryMissing(let url) {
            XCTAssertEqual(url, missingDirectory)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsOutsideSandbox() throws {
        let fixture = try makeFixture()
        let outsideDirectory = try makeTemporaryDirectory()

        do {
            _ = try fixture.service.createFile(named: "Outside.txt", in: outsideDirectory)
            XCTFail("Expected sandbox rejection")
        } catch SandboxAccessError.outsideExperimentalSandbox {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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
        let unrestrictedPolicy: SandboxFileAccessPolicy
        let failingFileManager: FailingFileManager?
    }

    private func makeFixture(useFailingManager: Bool = false) throws -> Fixture {
        let sandbox = try SandboxFixture(testCase: self)
        let left = try sandbox.temporaryDirectory.folder("AllowedSandbox/Left")
        let right = try sandbox.temporaryDirectory.folder("AllowedSandbox/Right")
        if useFailingManager {
            let failingFileManager = FailingFileManager()
            let accessProbe = SandboxFileAccessPolicy.AccessProbe(
                fileExists: { failingFileManager.fileExists(atPath: $0) },
                isReadableFile: { FileManager.default.isReadableFile(atPath: $0) },
                isWritableFile: { FileManager.default.isWritableFile(atPath: $0) }
            )
            let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandbox.root, accessProbe: accessProbe)
            return Fixture(root: sandbox.root, left: left, right: right, service: FileOperationService(fileManager: failingFileManager, accessPolicy: policy), unrestrictedPolicy: sandbox.unrestrictedPolicy, failingFileManager: failingFileManager)
        }
        return Fixture(root: sandbox.root, left: left, right: right, service: sandbox.fileOperationService(), unrestrictedPolicy: sandbox.unrestrictedPolicy, failingFileManager: nil)
    }

    private func assertOverlappingSelectionIsRejected(
        operation: (FileOperationService, URL, URL, URL) async throws -> FileOperationResult
    ) async throws {
        let fixture = try makeFixture()
        let parent = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let child = parent.appendingPathComponent("Child.txt")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try "child contents".write(to: child, atomically: true, encoding: .utf8)

        do {
            _ = try await operation(fixture.service, parent, child, fixture.right)
            XCTFail("Expected overlapping source rejection")
        } catch FileOperationError.overlappingSources(let ancestor, let descendant) {
            XCTAssertEqual(ancestor, parent)
            XCTAssertEqual(descendant, child)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.path))
        XCTAssertEqual(try String(contentsOf: child), "child contents")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(parent.lastPathComponent).path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TemporaryDirectoryFixture(testCase: self).root
    }
}

private struct RecordedFileOperation: Equatable {
    let source: URL
    let destination: URL
}

private final class ScriptedStreamingCopier: FileOperationStreamingCopying {
    let chunkSize: Int
    let cancelsAfterFirstChunk: Bool

    init(chunkSize: Int, cancelsAfterFirstChunk: Bool = false) {
        self.chunkSize = chunkSize
        self.cancelsAfterFirstChunk = cancelsAfterFirstChunk
    }

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        let data = try Data(contentsOf: source)
        var copied = Data()
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            copied.append(data[offset..<end])
            try await progress(end - offset)
            if cancelsAfterFirstChunk { throw CancellationError() }
            offset = end
        }
        try copied.write(to: destination)
    }
}

private final class FailingStreamingCopier: FileOperationStreamingCopying {
    private let failingSource: URL

    init(failingSource: URL) {
        self.failingSource = failingSource.standardizedFileURL
    }

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        if source.standardizedFileURL == failingSource { throw CocoaError(.fileReadNoPermission) }
        let data = try Data(contentsOf: source)
        try data.write(to: destination)
        try await progress(data.count)
    }
}

private final class PartialFailureStreamingCopier: FileOperationStreamingCopying {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        let data = try Data(contentsOf: source)
        try data.write(to: destination)
        try await progress(data.count)
        throw error
    }
}

private final class FailingFileManager: FileOperationFileManaging {
    var failCopyFromURL: URL?
    var failMoveToURL: URL?
    var moveFailureError: Error = CocoaError(.fileWriteUnknown)
    var failRemoveURL: URL?
    var failBackupRemoval = false
    var failStagingRemoval = false
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
        if failStagingRemoval, URL.lastPathComponent.hasPrefix(".pulsefiles-copy") || URL.lastPathComponent.hasPrefix(".pulsefiles-move") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: URL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }

    func createEmptyFile(at url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
    }

    func destinationOfSymbolicLink(atPath path: String) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destPath)
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


#if os(macOS)
private let metadataTestExtendedAttribute = "com.pulsefiles.tests.metadata"

private func setTestExtendedAttribute(on url: URL) throws {
    let value = Array("pulsefiles".utf8)
    guard setxattr(url.path, metadataTestExtendedAttribute, value, value.count, 0, 0) == 0 else {
        let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        if errno == ENOTSUP || errno == EOPNOTSUPP { throw XCTSkip("Extended attributes are unavailable: \(error.localizedDescription)") }
        throw error
    }
}

private func testExtendedAttribute(on url: URL) throws -> Data {
    let size = getxattr(url.path, metadataTestExtendedAttribute, nil, 0, 0, 0)
    guard size >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    var value = [UInt8](repeating: 0, count: size)
    guard getxattr(url.path, metadataTestExtendedAttribute, &value, value.count, 0, 0) >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return Data(value)
}
#endif

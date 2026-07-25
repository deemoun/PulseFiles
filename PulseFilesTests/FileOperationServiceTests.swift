import XCTest
#if os(macOS)
import Darwin
#endif
@testable import PulseFiles

private final class CloudPlaceholderState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPlaceholder: Bool
    private var storedUnavailable = false

    init(placeholder: Bool) { storedPlaceholder = placeholder }
    var placeholder: Bool { get { lock.withLock { storedPlaceholder } } set { lock.withLock { storedPlaceholder = newValue } } }
    var unavailable: Bool { get { lock.withLock { storedUnavailable } } set { lock.withLock { storedUnavailable = newValue } } }
}

private final class TestCloudDownloadPreparer: FileOperationCloudDownloadPreparing, @unchecked Sendable {
    let action: @Sendable (URL) async throws -> Bool
    init(action: @escaping @Sendable (URL) async throws -> Bool) { self.action = action }
    func prepareDownload(for url: URL) async throws -> Bool { try await action(url) }
}

final class FileOperationServiceTests: XCTestCase {
    func testOperationContextMarksBlockedCancellationAsUnknownUntilWorkerCanFinish() {
        let context = FileOperationContext()
        let item = URL(fileURLWithPath: "/tmp/blocked-item")
        context.beginBlockingCall(for: item)
        context.abandon()

        XCTAssertEqual(context.currentItem, item)
        XCTAssertTrue(context.needsVerification)
        XCTAssertFalse(FileOperationResult.unknownAfterAbandoning(currentItem: context.currentItem).wasCancelled)
    }

    func testCloudPlaceholderDownloadsThenCopiesWithPreparationProgress() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cloud-only.txt")
        try Data("downloaded".utf8).write(to: source)
        let state = CloudPlaceholderState(placeholder: true)
        let preparer = TestCloudDownloadPreparer { _ in
            state.placeholder = false
            return true
        }
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
            url == source ? .init(isICloudPlaceholder: state.placeholder) : .init()
        }, cloudDownloadPreparer: preparer)
        var progress: [FileOperationProgress] = []

        let result = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: { progress.append($0) })

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Cloud-only.txt")), "downloaded")
        XCTAssertTrue(progress.contains { $0.isPreparingTransfer && $0.currentItemName.contains("Downloading") })
    }

    func testCloudDownloadCancellationDoesNotMutateFiles() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cloud-only.txt")
        try Data("placeholder".utf8).write(to: source)
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
            url == source ? .init(isICloudPlaceholder: true) : .init()
        }, cloudDownloadPreparer: TestCloudDownloadPreparer { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return true
        })

        let task = Task { await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(source.lastPathComponent).path))
    }

    func testCloudDownloadUnavailableProviderPreservesSafeFailure() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cloud-only.txt")
        try Data("placeholder".utf8).write(to: source)
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
            url == source ? .init(isICloudPlaceholder: true) : .init()
        }, cloudDownloadPreparer: TestCloudDownloadPreparer { _ in false })

        do {
            _ = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
            XCTFail("Expected unavailable download provider to preserve placeholder failure")
        } catch FileOperationError.iCloudItemNotDownloaded(let rejectedURL) {
            XCTAssertEqual(rejectedURL, source)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(source.lastPathComponent).path))
    }

    func testCloudDownloadRevalidatesAvailabilityBeforeMutation() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cloud-only.txt")
        try Data("placeholder".utf8).write(to: source)
        let state = CloudPlaceholderState(placeholder: true)
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
            url == source ? .init(isAvailable: !state.unavailable, isICloudPlaceholder: state.placeholder) : .init()
        }, cloudDownloadPreparer: TestCloudDownloadPreparer { _ in
            state.placeholder = false
            state.unavailable = true
            return true
        })

        do {
            _ = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
            XCTFail("Expected post-download availability revalidation")
        } catch FileOperationError.volumeUnavailable(let rejectedURL) {
            XCTAssertEqual(rejectedURL, source)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(source.lastPathComponent).path))
    }

    func testICloudPlaceholderIsRejectedBeforeConflictResolution() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cloud-only.txt")
        try Data("placeholder".utf8).write(to: source)
        let service = FileOperationService(
            fileManager: .default,
            accessPolicy: fixture.unrestrictedPolicy,
            pathSafetyStateProvider: { url in
                url == source ? FileOperationPathSafetyState(isICloudPlaceholder: true) : FileOperationPathSafetyState()
            }
        )

        do {
            _ = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in
                XCTFail("A cloud-only item must be rejected before conflict handling")
                return .cancel
            }, progressHandler: nil)
            XCTFail("Expected an iCloud placeholder error")
        } catch FileOperationError.iCloudItemNotDownloaded(let rejectedURL) {
            XCTAssertEqual(rejectedURL, source)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(source.lastPathComponent).path))
    }

    func testFinderAliasCopyPreservesOpaqueAliasObjectAndMetadata() async throws {
        let fixture = try makeFixture()
        let alias = fixture.left.appendingPathComponent("Reference.alias")
        try Data("alias data".utf8).write(to: alias)
        try setTestExtendedAttribute(on: alias)
        let service = aliasAwareService(for: [alias], fixture: fixture)
        let result = try await service.copy(FileOperationRequest(sources: [alias], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let copiedAlias = fixture.right.appendingPathComponent(alias.lastPathComponent)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try Data(contentsOf: copiedAlias), Data("alias data".utf8))
        XCTAssertEqual(try testExtendedAttribute(on: copiedAlias), Data("pulsefiles".utf8))
    }

    func testFinderAliasMoveAndRenameTreatAliasAsOpaqueObject() async throws {
        let fixture = try makeFixture()
        let alias = fixture.left.appendingPathComponent("Reference.alias")
        try Data("alias data".utf8).write(to: alias)
        let movedAlias = fixture.right.appendingPathComponent(alias.lastPathComponent)
        let service = aliasAwareService(for: [alias, movedAlias], fixture: fixture)
        let moveResult = try await service.move(FileOperationRequest(sources: [alias], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let renameResult = try await service.rename(movedAlias, to: "Renamed.alias", progressHandler: nil)
        XCTAssertTrue(moveResult.succeededCompletely)
        XCTAssertTrue(renameResult.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: alias.path))
        XCTAssertEqual(try Data(contentsOf: fixture.right.appendingPathComponent("Renamed.alias")), Data("alias data".utf8))
    }

    func testFinderAliasTrashAndDeleteTreatAliasAsOpaqueObject() async throws {
        let fixture = try makeFixture()
        let deletedAlias = fixture.left.appendingPathComponent("Delete.alias")
        try Data("delete alias".utf8).write(to: deletedAlias)
        let deleteResult = try await aliasAwareService(for: [deletedAlias], fixture: fixture).delete([deletedAlias], progressHandler: nil)
        XCTAssertTrue(deleteResult.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedAlias.path))
        let trashedAlias = fixture.left.appendingPathComponent("Trash.alias")
        try Data("trash alias".utf8).write(to: trashedAlias)
        let trashResult = try await aliasAwareService(for: [trashedAlias], fixture: fixture).trash([trashedAlias], progressHandler: nil)
        XCTAssertTrue(trashResult.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashedAlias.path))
    }

    func testFinderAliasConflictReplacementRollsBackWhenAliasCopyFails() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let alias = fixture.left.appendingPathComponent("Reference.alias")
        let destination = fixture.right.appendingPathComponent(alias.lastPathComponent)
        try Data("new alias".utf8).write(to: alias)
        try Data("existing alias".utf8).write(to: destination)
        fixture.failingFileManager?.failCopyFromURL = alias
        let service = FileOperationService(fileManager: fixture.failingFileManager!, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
                [alias, destination].contains(url.standardizedFileURL) ? .init(isFinderAlias: true) : .init()
            })
        let result = try await service.copy(FileOperationRequest(sources: [alias], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)
        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertEqual(try String(contentsOf: destination), "existing alias")
        XCTAssertEqual(try String(contentsOf: alias), "new alias")
    }

    func testReadOnlyDestinationIsRejectedBeforeCopy() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Source.txt")
        try Data("source".utf8).write(to: source)
        let service = FileOperationService(
            fileManager: .default,
            accessPolicy: fixture.unrestrictedPolicy,
            pathSafetyStateProvider: { url in
                url == fixture.right ? FileOperationPathSafetyState(isReadOnlyVolume: true) : FileOperationPathSafetyState()
            }
        )

        do {
            _ = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)
            XCTFail("Expected a read-only volume error")
        } catch FileOperationError.readOnlyVolume(let rejectedURL) {
            XCTAssertEqual(rejectedURL, fixture.right)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testUnavailableSourceVolumeIsRejectedBeforeMove() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Disconnected.txt")
        try Data("source".utf8).write(to: source)
        let service = FileOperationService(
            fileManager: .default,
            accessPolicy: fixture.unrestrictedPolicy,
            pathSafetyStateProvider: { url in
                url == source ? FileOperationPathSafetyState(isAvailable: false) : FileOperationPathSafetyState()
            }
        )

        do {
            _ = try await service.move(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .replace }, progressHandler: nil)
            XCTFail("Expected an unavailable-volume error")
        } catch FileOperationError.volumeUnavailable(let rejectedURL) {
            XCTAssertEqual(rejectedURL, source)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyPreservesPackageDirectoryAndSymbolicLinkWithoutResolvingLink() async throws {
        let fixture = try makeFixture()
        let package = fixture.left.appendingPathComponent("Example.bundle", isDirectory: true)
        let packageContents = package.appendingPathComponent("Contents", isDirectory: true)
        let target = fixture.left.appendingPathComponent("Target.txt")
        let link = fixture.left.appendingPathComponent("Target Alias")
        try FileManager.default.createDirectory(at: packageContents, withIntermediateDirectories: true)
        try Data("package data".utf8).write(to: packageContents.appendingPathComponent("Info.txt"))
        try Data("target data".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [package, link], destinationDirectory: fixture.right),
            conflictHandler: { _ in .cancel },
            progressHandler: nil
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Example.bundle/Contents/Info.txt").path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: fixture.right.appendingPathComponent("Target Alias").path),
            target.path
        )
    }

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


    func testCapacityPreflightReportsSufficientSpaceForCopy() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Sized.txt")
        try Data(repeating: 1, count: 12).write(to: source)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, destinationCapacityProvider: { _ in 12 })

        let result = try await service.transferCapacityPreflight(for: FileOperationRequest(sources: [source], destinationDirectory: fixture.right), isMove: false)

        XCTAssertEqual(result, .sufficient(required: 12, available: 12))
    }

    func testCapacityPreflightRejectsInsufficientSpaceBeforeConflictResolution() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Sized.txt")
        try Data(repeating: 1, count: 12).write(to: source)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, destinationCapacityProvider: { _ in 11 })

        do {
            _ = try await service.copy(FileOperationRequest(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in
                XCTFail("Conflict resolution must not run after an insufficient-capacity preflight")
                return .cancel
            }, progressHandler: nil)
            XCTFail("Expected insufficient capacity error")
        } catch FileOperationError.insufficientDestinationCapacity(let required, let available) {
            XCTAssertEqual(required, 12)
            XCTAssertEqual(available, 11)
        }
    }

    func testCapacityPreflightReportsUnknownCapacity() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Sized.txt")
        try Data(repeating: 1, count: 12).write(to: source)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, destinationCapacityProvider: { _ in nil })

        let result = try await service.transferCapacityPreflight(for: FileOperationRequest(sources: [source], destinationDirectory: fixture.right), isMove: false)

        XCTAssertEqual(result, .cannotVerify(required: 12))
    }

    func testCapacityPreflightAppliesToCrossVolumeMoves() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Sized.txt")
        try Data(repeating: 1, count: 12).write(to: source)
        let service = FileOperationService(
            fileManager: FileManager.default,
            accessPolicy: fixture.unrestrictedPolicy,
            destinationCapacityProvider: { _ in 11 },
            volumeIdentifierProvider: { $0.path.hasPrefix(fixture.left.path) ? "source" : "destination" }
        )

        let result = try await service.transferCapacityPreflight(for: FileOperationRequest(sources: [source], destinationDirectory: fixture.right), isMove: true)

        XCTAssertEqual(result, .insufficient(required: 12, available: 11))
    }

    func testCapacityPreflightConservativelyIncludesReplacementSize() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Sized.txt")
        let destination = fixture.right.appendingPathComponent("Sized.txt")
        try Data(repeating: 1, count: 12).write(to: source)
        try Data(repeating: 1, count: 100).write(to: destination)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, destinationCapacityProvider: { _ in 11 })

        let result = try await service.transferCapacityPreflight(for: FileOperationRequest(sources: [source], destinationDirectory: fixture.right), isMove: false)

        XCTAssertEqual(result, .insufficient(required: 12, available: 11))
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

    func testIterativeCopyHandlesDeeplyNestedFixture() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Deep", isDirectory: true)
        var leaf = source
        for index in 0..<300 {
            leaf.appendPathComponent("Level-\(index)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        let file = leaf.appendingPathComponent("Leaf.txt")
        try "deep contents".write(to: file, atomically: true, encoding: .utf8)

        let result = try await fixture.service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)

        XCTAssertTrue(result.succeededCompletely)
        let copiedLeaf = fixture.right.appendingPathComponent("Deep").appendingPathComponent(file.path.replacingOccurrences(of: source.path + "/", with: ""))
        XCTAssertEqual(try String(contentsOf: copiedLeaf), "deep contents")
    }

    func testCancellationDuringMetadataPlanningStopsTransfer() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Many files", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for index in 0..<256 {
            try Data([UInt8(index % 255)]).write(to: source.appendingPathComponent("\(index).txt"))
        }
        let planningStarted = expectation(description: "metadata planning progress")
        let task = Task {
            try await fixture.service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: { progress in
                if progress.isPreparingTransfer && progress.completedRecursiveItemCount == 1 {
                    planningStarted.fulfill()
                }
            })
        }
        await fulfillment(of: [planningStarted], timeout: 5)
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Many files").path))
    }

    func testIterativeCopyRestoresNestedDirectoryMetadataPostOrder() async throws {
        #if os(macOS)
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Parent", isDirectory: true)
        let childDirectory = source.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "contents".write(to: childDirectory.appendingPathComponent("Document.txt"), atomically: true, encoding: .utf8)
        let parentDate = Date(timeIntervalSince1970: 1_700_000_001)
        let childDate = Date(timeIntervalSince1970: 1_700_000_002)
        try FileManager.default.setAttributes([.modificationDate: parentDate], ofItemAtPath: source.path)
        try FileManager.default.setAttributes([.modificationDate: childDate], ofItemAtPath: childDirectory.path)

        let result = try await fixture.service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        XCTAssertTrue(result.cleanupWarnings.isEmpty)
        let copied = fixture.right.appendingPathComponent("Parent")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copied.path)[.modificationDate] as? Date, parentDate)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copied.appendingPathComponent("Child").path)[.modificationDate] as? Date, childDate)
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

    func testManagedStagingIsSameVolumeAtomicAndRemovedAfterSuccess() async throws {
        let fixture = try makeFixture(useFailingManager: true)
        let source = fixture.left.appendingPathComponent("Atomic.txt")
        let destination = fixture.right.appendingPathComponent("Atomic.txt")
        let stagingDirectory = fixture.root.appendingPathComponent("Replacement-\(UUID().uuidString)")
        try "complete".write(to: source, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            fileManager: fixture.failingFileManager!,
            accessPolicy: fixture.unrestrictedPolicy,
            replacementDirectoryProvider: { appropriateDestination in
                XCTAssertEqual(appropriateDestination, destination)
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
                return stagingDirectory
            }
        )

        let result = try await service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try String(contentsOf: destination), "complete")
        XCTAssertTrue(fixture.failingFileManager?.movedItems.contains {
            $0.source == stagingDirectory.appendingPathComponent("item") && $0.destination == destination
        } == true, "Final publication must be a rename from managed staging")
        XCTAssertEqual(
            try stagingDirectory.deletingLastPathComponent().resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier.map { String(describing: $0) },
            try destination.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier.map { String(describing: $0) }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: fixture.right, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.hasPrefix(".pulsefiles-") })
    }

    func testPartialFailureCleansManagedDirectoryWithoutPublishingPartialCopy() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Partial.txt")
        let stagingDirectory = fixture.root.appendingPathComponent("Replacement-\(UUID().uuidString)")
        try "partial contents".write(to: source, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            fileManager: .default,
            accessPolicy: fixture.unrestrictedPolicy,
            streamingCopier: PartialFailureStreamingCopier(error: CocoaError(.fileWriteUnknown)),
            replacementDirectoryProvider: { _ in
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
                return stagingDirectory
            }
        )

        let result = try await service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)

        XCTAssertEqual(result.failedItems.map(\.url), [source])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Partial.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: fixture.right, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.hasPrefix(".pulsefiles-") })
    }

    func testCancellationCleansManagedStagingDirectory() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Cancelled.txt")
        let stagingDirectory = fixture.root.appendingPathComponent("Replacement-\(UUID().uuidString)")
        try "cancelled contents".write(to: source, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            fileManager: .default,
            accessPolicy: fixture.unrestrictedPolicy,
            streamingCopier: PartialFailureStreamingCopier(error: CancellationError()),
            replacementDirectoryProvider: { _ in
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
                return stagingDirectory
            }
        )

        let result = try await service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Cancelled.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
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
        XCTAssertEqual(fixture.failingFileManager?.simulatedExistingStagingPathHits, 0)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: fixture.right, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.hasPrefix(".pulsefiles-") })
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
        XCTAssertTrue(fixture.failingFileManager?.movedItems.contains { $0.destination.lastPathComponent == "backup" } == true)
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
        XCTAssertFalse(result.cleanupWarnings[0].url.deletingLastPathComponent().standardizedFileURL == fixture.right.standardizedFileURL)
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
        XCTAssertFalse(result.cleanupWarnings[0].url.deletingLastPathComponent().standardizedFileURL == fixture.right.standardizedFileURL)
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

    func testStreamingCopyCoalescesFrequentProgressUpdates() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Large.bin")
        try Data(repeating: 7, count: 200).write(to: source)
        let copier = ScriptedStreamingCopier(chunkSize: 1)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)
        var progressEvents: [FileOperationProgress] = []

        let result = try await service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { progressEvents.append($0) }
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertLessThan(progressEvents.count, 10, "Chunk-level progress should not flood the main actor.")
        XCTAssertEqual(progressEvents.compactMap(\.completedByteCount).max(), 200)
    }

    func testTransferReportsIndeterminatePreparingProgressBeforeMetadataDiscovery() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Data.bin")
        try Data(repeating: 1, count: 4).write(to: source)
        var progressEvents: [FileOperationProgress] = []

        let result = try await fixture.service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { progressEvents.append($0) }
        )

        XCTAssertTrue(result.succeededCompletely)
        XCTAssertTrue(progressEvents.first?.isPreparingTransfer == true)
        XCTAssertEqual(progressEvents.first?.currentItemName, "Preparing transfer")
    }

    func testCancellationDuringPrescanReturnsCancelledWithoutCreatingDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for index in 0 ..< 100 {
            try Data(repeating: UInt8(index), count: 1_024).write(to: source.appendingPathComponent("\(index).bin"))
        }

        let task = Task {
            try await fixture.service.copy(
                FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
                conflictHandler: { _ in .replace },
                progressHandler: { _ in }
            )
        }
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Folder").path))
    }

    func testStreamingCopyCancellationLeavesNoStagedDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Data.bin")
        try Data(repeating: 1, count: 3 * 1_048_576).write(to: source)
        let copier = ScriptedStreamingCopier(chunkSize: 1_048_576, cancelsAfterFirstChunk: true)
        let service = FileOperationService(fileManager: FileManager.default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)

        let result = try await service.copy(
            FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { _ in }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Data.bin").path))
    }

    func testCancellationInNestedDirectoryPreservesCompletedTopLevelItems() async throws {
        let fixture = try makeFixture()
        let completed = fixture.left.appendingPathComponent("Completed.txt")
        let folder = fixture.left.appendingPathComponent("Folder", isDirectory: true)
        let nested = folder.appendingPathComponent("Nested.bin")
        try "complete".write(to: completed, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: nested)
        let copier = CancellingOnSourceStreamingCopier(sourceToCancel: nested)
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)

        let result = try await service.copy(
            FileOperationRequest(sources: [completed, folder], destinationDirectory: fixture.right),
            conflictHandler: { _ in .replace },
            progressHandler: { _ in }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.completedItems, [completed])
        XCTAssertEqual(try String(contentsOf: fixture.right.appendingPathComponent("Completed.txt")), "complete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Folder").path))
    }

    func testBlockingStreamingCopyDoesNotBlockMainActorProgressCallbacks() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Data.bin")
        try Data(repeating: 1, count: 4).write(to: source)
        let copier = BlockingStreamingCopier()
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, streamingCopier: copier)
        let started = expectation(description: "streaming copy started on its worker")
        let progress = expectation(description: "main-actor progress callback ran while copy is blocked")
        let mainActorWork = expectation(description: "main actor remained responsive")
        copier.onStarted = { started.fulfill() }

        let copyTask = Task {
            try await service.copy(
                FileOperationRequest(sources: [source], destinationDirectory: fixture.right),
                conflictHandler: { _ in .replace },
                progressHandler: { _ in
                    if copier.isStarted {
                        XCTAssertTrue(Thread.isMainThread)
                        progress.fulfill()
                    }
                }
            )
        }

        await fulfillment(of: [started, progress], timeout: 2)
        await MainActor.run { mainActorWork.fulfill() }
        await fulfillment(of: [mainActorWork], timeout: 1)

        copier.releaseCopy()
        let result = try await copyTask.value
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertEqual(try Data(contentsOf: fixture.right.appendingPathComponent("Data.bin")).count, 4)
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


    func testCreateFileAllowsNonexistentDestinationWhenParentIsAccessibleInSandbox() async throws {
        let fixture = try makeFixture()
        let destination = fixture.left.appendingPathComponent("Brand New.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let result = try await fixture.service.createFile(named: "Brand New.txt", in: fixture.left)
        let created = try XCTUnwrap(result.completedItems.first)

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

    func testUnrestrictedModeAllowsCreationWhenNonexistentDestinationParentIsWritable() async throws {
        let fixture = try makeFixture()
        let externalDirectory = try makeTemporaryDirectory()
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy)
        let destination = externalDirectory.appendingPathComponent("External New.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let result = try await service.createFile(named: "External New.txt", in: externalDirectory)
        let created = try XCTUnwrap(result.completedItems.first)

        XCTAssertEqual(created, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCreateFolderCreatesDirectoryInSandbox() async throws {
        let fixture = try makeFixture()

        let result = try await fixture.service.createFolder(named: "New Folder", in: fixture.left)
        let created = try XCTUnwrap(result.completedItems.first)

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(created, fixture.left.appendingPathComponent("New Folder", isDirectory: true))
    }

    func testCreateFileCreatesEmptyFileInSandbox() async throws {
        let fixture = try makeFixture()

        let result = try await fixture.service.createFile(named: "Notes.txt", in: fixture.left)
        let created = try XCTUnwrap(result.completedItems.first)

        var isDirectory = ObjCBool(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertEqual(try Data(contentsOf: created), Data())
    }

    func testCreateFolderRejectsDuplicateName() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.left.appendingPathComponent("Existing"), withIntermediateDirectories: false)

        do {
            _ = try await fixture.service.createFolder(named: "Existing", in: fixture.left)
            XCTFail("Expected duplicate creation rejection")
        } catch FileNameValidator.ValidationError.duplicateName {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsDuplicateName() async throws {
        let fixture = try makeFixture()
        let existing = fixture.left.appendingPathComponent("Existing.txt")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)

        do {
            _ = try await fixture.service.createFile(named: "Existing.txt", in: fixture.left)
            XCTFail("Expected duplicate creation rejection")
        } catch FileNameValidator.ValidationError.duplicateName {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsInvalidName() async throws {
        let fixture = try makeFixture()

        do {
            _ = try await fixture.service.createFile(named: "../Bad.txt", in: fixture.left)
            XCTFail("Expected invalid name rejection")
        } catch FileNameValidator.ValidationError.containsSlash {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFolderRejectsMissingDestinationDirectory() async throws {
        let fixture = try makeFixture()
        let missingDirectory = fixture.left.appendingPathComponent("Missing")

        do {
            _ = try await fixture.service.createFolder(named: "New Folder", in: missingDirectory)
            XCTFail("Expected missing destination directory rejection")
        } catch FileOperationError.destinationDirectoryMissing(let url) {
            XCTAssertEqual(url, missingDirectory)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileRejectsOutsideSandbox() async throws {
        let fixture = try makeFixture()
        let outsideDirectory = try makeTemporaryDirectory()

        do {
            _ = try await fixture.service.createFile(named: "Outside.txt", in: outsideDirectory)
            XCTFail("Expected sandbox rejection")
        } catch SandboxAccessError.outsideExperimentalSandbox {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateFileReportsCancellationBeforePreflightMutation() async throws {
        let fixture = try makeFixture()

        let result = try await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.service.createFile(named: "Cancelled.txt", in: fixture.left)
        }.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.needsVerification)
        XCTAssertTrue(result.completedItems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.left.appendingPathComponent("Cancelled.txt").path))
    }

    func testCreateFolderReportsFileManagerError() async throws {
        let fixture = try makeFixture()
        let fileManager = FailingFileManager()
        fileManager.creationFailure = CocoaError(.fileWriteNoPermission)
        let service = FileOperationService(fileManager: fileManager, accessPolicy: fixture.unrestrictedPolicy)

        do {
            _ = try await service.createFolder(named: "Denied", in: fixture.left)
            XCTFail("Expected creation error")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
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

    func testUndoReversesSuccessfulMove() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Undo.txt")
        try Data("undo".utf8).write(to: source)
        let move = try await fixture.service.move(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let recovery = try XCTUnwrap(move.recovery)
        let result = try await fixture.service.undo(recovery, progressHandler: nil)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testUndoRemovesOnlyTheUnchangedCopyDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Copy undo.txt")
        try Data("copy".utf8).write(to: source)
        let copy = try await fixture.service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        let recovery = try XCTUnwrap(copy.recovery)
        XCTAssertEqual(recovery.kind, .copy)
        let result = try await fixture.service.undo(recovery, progressHandler: nil)
        XCTAssertTrue(result.succeededCompletely)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent(source.lastPathComponent).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRecoveryTitlesDescribeTheExactUndoAction() {
        let item = FileOperationRecovery.Item(originalURL: URL(fileURLWithPath: "/original"), destinationURL: URL(fileURLWithPath: "/destination"))
        XCTAssertEqual(FileOperationRecovery(kind: .copy, items: [item]).undoTitle, "Undo Copy")
        XCTAssertEqual(FileOperationRecovery(kind: .trash, items: [item]).undoTitle, "Undo Move to Trash")
    }

    func testUndoCopyRejectsReplacementAtDestination() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Copy replacement.txt")
        let destination = fixture.right.appendingPathComponent(source.lastPathComponent)
        try Data("copy".utf8).write(to: source)
        let copy = try await fixture.service.copy(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        try FileManager.default.removeItem(at: destination)
        try Data("replacement".utf8).write(to: destination)
        do { _ = try await fixture.service.undo(try XCTUnwrap(copy.recovery), progressHandler: nil); XCTFail("Expected identity rejection") }
        catch FileOperationError.undoUnavailable { }
        XCTAssertEqual(try String(contentsOf: destination), "replacement")
    }

    func testUndoRejectsOriginalPathConflict() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Conflict.txt")
        try Data("source".utf8).write(to: source)
        let move = try await fixture.service.move(.init(sources: [source], destinationDirectory: fixture.right), conflictHandler: { _ in .cancel }, progressHandler: nil)
        try Data("replacement".utf8).write(to: source)
        do { _ = try await fixture.service.undo(try XCTUnwrap(move.recovery), progressHandler: nil); XCTFail("Expected conflict") }
        catch FileOperationError.destinationExists(let url) { XCTAssertEqual(url, source) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.right.appendingPathComponent("Conflict.txt").path))
    }

    func testUndoRejectsRemovedDestinationVolume() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Volume.txt")
        let destination = fixture.right.appendingPathComponent("Volume.txt")
        try Data("source".utf8).write(to: source)
        let recovery = FileOperationRecovery(kind: .move, items: [.init(originalURL: source, destinationURL: destination)])
        let service = FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in url == destination ? .init(isAvailable: false) : .init() })
        do { _ = try await service.undo(recovery, progressHandler: nil); XCTFail("Expected volume error") }
        catch FileOperationError.volumeUnavailable(let url) { XCTAssertEqual(url, destination) }
    }

    func testUndoRejectsDeniedAccess() async throws {
        let fixture = try makeFixture()
        let source = fixture.left.appendingPathComponent("Denied.txt")
        let destination = fixture.right.appendingPathComponent("Denied.txt")
        try Data("destination".utf8).write(to: destination)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: fixture.left)
        let service = FileOperationService(fileManager: .default, accessPolicy: policy)
        do { _ = try await service.undo(.init(kind: .move, items: [.init(originalURL: source, destinationURL: destination)]), progressHandler: nil); XCTFail("Expected access denial") }
        catch SandboxAccessError.outsideExperimentalSandbox(let url) { XCTAssertEqual(url, destination) }
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

    private func aliasAwareService(for aliases: [URL], fixture: Fixture) -> FileOperationService {
        let aliasPaths = Set(aliases.map { $0.standardizedFileURL.path })
        return FileOperationService(fileManager: .default, accessPolicy: fixture.unrestrictedPolicy, pathSafetyStateProvider: { url in
            aliasPaths.contains(url.standardizedFileURL.path) ? .init(isFinderAlias: true) : .init()
        })
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

private final class CancellingOnSourceStreamingCopier: FileOperationStreamingCopying {
    private let sourceToCancel: URL

    init(sourceToCancel: URL) {
        self.sourceToCancel = sourceToCancel.standardizedFileURL
    }

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        let data = try Data(contentsOf: source)
        if source.standardizedFileURL == sourceToCancel {
            try data.prefix(1).write(to: destination)
            try await progress(1)
            throw CancellationError()
        }
        try data.write(to: destination)
        try await progress(data.count)
    }
}

private final class BlockingStreamingCopier: FileOperationStreamingCopying {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var hasStarted = false
    var onStarted: (() -> Void)?

    func copyFile(from source: URL, to destination: URL, progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        lock.lock()
        hasStarted = true
        let started = onStarted
        lock.unlock()
        started?()
        try await progress(1)
        releaseSemaphore.wait()
        try Task.checkCancellation()
        try Data(contentsOf: source).write(to: destination)
        try await progress(3)
    }

    var isStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasStarted
    }

    func releaseCopy() {
        releaseSemaphore.signal()
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
    var creationFailure: Error?
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
        if failBackupRemoval, URL.lastPathComponent == "backup" {
            throw CocoaError(.fileWriteNoPermission)
        }
        if failStagingRemoval, URL.lastPathComponent == "item" || ((try? FileManager.default.contentsOfDirectory(at: URL, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.hasPrefix(".pulsefiles-operation-") }) == true) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: URL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        if let creationFailure { throw creationFailure }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }

    func createEmptyFile(at url: URL) throws {
        if let creationFailure { throw creationFailure }
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

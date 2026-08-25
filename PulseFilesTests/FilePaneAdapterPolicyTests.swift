import XCTest
@testable import PulseFiles
@testable import PulseFilesPane

final class FilePaneAdapterPolicyTests: XCTestCase {
    func testDropPolicyMovesOnlyInternalSameVolumeDrags() {
        let policy = DropTransferPolicy(volumeIdentifierProvider: { $0.path.hasPrefix("/same") ? "one" : "two" })
        XCTAssertEqual(policy.resolvedOperation(for: [URL(fileURLWithPath: "/same/a")], destinationDirectory: URL(fileURLWithPath: "/same/d"), isInternalAppDrag: true, optionForcesCopy: false), .move)
        XCTAssertEqual(policy.resolvedOperation(for: [URL(fileURLWithPath: "/other/a")], destinationDirectory: URL(fileURLWithPath: "/same/d"), isInternalAppDrag: true, optionForcesCopy: false), .copy)
        XCTAssertEqual(policy.resolvedOperation(for: [URL(fileURLWithPath: "/same/a")], destinationDirectory: URL(fileURLWithPath: "/same/d"), isInternalAppDrag: true, optionForcesCopy: true), .copy)
    }

    func testDropDecisionRejectsMoveToSameDirectoryAndDirectoryDescendant() {
        let source = URL(fileURLWithPath: "/tmp/folder")
        XCTAssertFalse(FilePaneDropCoordinator.permitsDrop(sources: [source], destination: URL(fileURLWithPath: "/tmp"), operation: .move, directoryValues: [source: true, URL(fileURLWithPath: "/tmp"): true]))
        let child = source.appendingPathComponent("child")
        XCTAssertFalse(FilePaneDropCoordinator.permitsDrop(sources: [source], destination: child, operation: .copy, directoryValues: [source: true, child: true]))
    }

    func testReloadPolicyReloadsImmediatelyOutsideEdit() {
        XCTAssertEqual(InlineRenameReloadPolicy.decision(isEditing: false, itemExists: false), .reloadNow)
    }
}

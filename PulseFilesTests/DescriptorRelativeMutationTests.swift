#if os(macOS)
import XCTest
import Darwin
@testable import PulseFiles

final class DescriptorRelativeMutationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PulseFiles-descriptor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCheckedSourceSwapIsRejectedBeforeMutation() throws {
        let parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = parent.appendingPathComponent("source")
        try Data("original".utf8).write(to: source)
        let capability = try OpenDirectoryCapability(directory: parent)
        defer { capability.close() }
        let identity = try capability.itemIdentity(named: "source")
        try FileManager.default.removeItem(at: source)
        try Data("replacement".utf8).write(to: source)
        XCTAssertThrowsError(try capability.requireItem(named: "source", identity: identity))
    }

    func testSymlinkedDestinationComponentCannotBecomeMutationParent() throws {
        let trusted = root.appendingPathComponent("trusted")
        let outside = root.appendingPathComponent("outside")
        let swapped = root.appendingPathComponent("swapped")
        try FileManager.default.createDirectory(at: trusted, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: swapped, withDestinationURL: outside)
        XCTAssertThrowsError(try OpenDirectoryCapability(directory: swapped))
    }

    func testOpenedDestinationParentRemainsUsableAfterPathIsReplaced() throws {
        let parent = root.appendingPathComponent("destination")
        let replacement = root.appendingPathComponent("destination-replacement")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let capability = try OpenDirectoryCapability(directory: parent)
        defer { capability.close() }
        try FileManager.default.moveItem(at: parent, to: replacement)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try capability.revalidate()
        let name = "created-through-original-fd"
        let fd = name.withCString { Darwin.openat(capability.fileDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644) }
        XCTAssertGreaterThanOrEqual(fd, 0)
        Darwin.close(fd)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.appendingPathComponent(name).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path))
    }

    func testStagingCandidateSymlinkCannotRedirectDescriptorRelativeCreation() throws {
        let staging = root.appendingPathComponent("staging")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let protectedFile = outside.appendingPathComponent("protected")
        try Data("unchanged".utf8).write(to: protectedFile)

        // This models an attacker replacing a selected staging name after
        // preflight but before the creation syscall.
        let candidate = staging.appendingPathComponent(".pulsefiles-copy-candidate")
        try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: protectedFile)
        let capability = try OpenDirectoryCapability(directory: staging)
        defer { capability.close() }

        XCTAssertThrowsError(try capability.openNewRegularFile(named: candidate.lastPathComponent))
        XCTAssertEqual(try String(contentsOf: protectedFile), "unchanged")
    }
}
#endif

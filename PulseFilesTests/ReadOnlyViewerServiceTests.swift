import Foundation
import XCTest
@testable import PulseFiles

final class ReadOnlyViewerServiceTests: XCTestCase {
    func testDetectsUTF8AndUTF16Text() {
        XCTAssertEqual(ReadOnlyViewerService.detectedTextEncoding(in: Data("hello\n".utf8)), .utf8)
        XCTAssertEqual(ReadOnlyViewerService.detectedTextEncoding(in: Data([0xFF, 0xFE, 0x41, 0x00])), .utf16LittleEndian)
    }

    func testBinaryDataUsesHexWithOffsetsAndASCII() {
        let snapshot = ReadOnlyViewerService.snapshot(data: Data([0x41, 0x00, 0xFF]), bytesRead: 3, isComplete: true, isTruncated: false)
        XCTAssertEqual(snapshot.kind, .hex)
        XCTAssertTrue(snapshot.content.contains("00000000"))
        XCTAssertTrue(snapshot.content.contains("41 00 FF"))
        XCTAssertTrue(snapshot.content.contains("|A..|"))
    }

    func testIncrementalReadCapsRetainedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("large.txt")
        try Data(repeating: 0x41, count: 128).write(to: file)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: directory)
        let service = ReadOnlyViewerService(accessPolicy: policy, limits: .init(chunkSize: 8, retainedByteCount: 24))
        var final: ViewerSnapshot?
        for try await snapshot in service.snapshots(for: file) { final = snapshot }
        XCTAssertEqual(final?.content.count, 24)
        XCTAssertEqual(final?.bytesRead, 24)
        XCTAssertEqual(final?.isTruncated, true)
        XCTAssertEqual(final?.isComplete, false)
    }

    func testDeniedURLFailsBeforeReading() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = ReadOnlyViewerService(accessPolicy: .init(isEnabled: true, rootURL: root))
        do {
            for try await _ in service.snapshots(for: outside) {}
            XCTFail("Expected sandbox validation failure")
        } catch {
            XCTAssertEqual(error as? SandboxAccessError, .outsideExperimentalSandbox(outside))
        }
    }
}

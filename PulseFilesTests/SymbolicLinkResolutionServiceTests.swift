import XCTest
@testable import PulseFiles

final class SymbolicLinkResolutionServiceTests: XCTestCase {
    func testResolvesOneRelativeHopWithoutFollowingAChain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data()))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target")
        XCTAssertEqual(try SymbolicLinkResolutionService().resolveOneHop(at: link), target)
    }

    func testRejectsBrokenLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
        XCTAssertThrowsError(try SymbolicLinkResolutionService().resolveOneHop(at: link))
    }
}

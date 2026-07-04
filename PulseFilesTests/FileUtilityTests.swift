import XCTest
@testable import PulseFiles

final class FileUtilityTests: XCTestCase {
    func testShellEscapingSingleQuotes() {
        XCTAssertEqual(PathUtilities.shellEscaped("/tmp/it's here"), "'/tmp/it'\\''s here'")
    }

    func testRelativePathGeneration() {
        let root = URL(fileURLWithPath: "/Users/example/Projects/PulseFiles")
        let child = URL(fileURLWithPath: "/Users/example/Projects/PulseFiles/PulseFiles/App/Main.swift")
        XCTAssertEqual(PathUtilities.relativePath(from: root, to: child), "PulseFiles/App/Main.swift")
    }

    func testRelativePathGenerationForSibling() {
        let root = URL(fileURLWithPath: "/Users/example/Projects/PulseFiles")
        let sibling = URL(fileURLWithPath: "/Users/example/Projects/Other/readme.md")
        XCTAssertEqual(PathUtilities.relativePath(from: root, to: sibling), "../Other/readme.md")
    }
}

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

final class FileNameValidatorTests: XCTestCase {
    func testAcceptsOrdinaryFileNames() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertEqual(try FileNameValidator.validate("Report.txt", in: directory), "Report.txt")
    }

    func testTrimsSurroundingWhitespace() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertEqual(try FileNameValidator.validate("  Report.txt\n", in: directory), "Report.txt")
    }

    func testRejectsEmptyAndWhitespaceOnlyNames() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertThrowsError(try FileNameValidator.validate("", in: directory)) { error in
            XCTAssertEqual(error as? FileNameValidator.ValidationError, .empty)
        }
        XCTAssertThrowsError(try FileNameValidator.validate("   \n", in: directory)) { error in
            XCTAssertEqual(error as? FileNameValidator.ValidationError, .empty)
        }
    }

    func testRejectsSlashRelativePathNullAndReservedNames() throws {
        let directory = try makeTemporaryDirectory()
        let cases: [(String, FileNameValidator.ValidationError)] = [
            ("folder/file", .containsSlash),
            (".", .reservedRelativePath),
            ("..", .reservedRelativePath),
            ("bad\0name", .containsNullCharacter),
            (".DS_Store", .reservedName(".DS_Store"))
        ]

        for (name, expectedError) in cases {
            XCTAssertThrowsError(try FileNameValidator.validate(name, in: directory), "Expected \(name) to be rejected") { error in
                XCTAssertEqual(error as? FileNameValidator.ValidationError, expectedError)
            }
        }
    }

    func testRejectsExactDuplicateName() throws {
        let directory = try makeTemporaryDirectory()
        let existingURL = directory.appendingPathComponent("Existing.txt")
        try Data().write(to: existingURL)

        XCTAssertThrowsError(try FileNameValidator.validate("Existing.txt", in: directory)) { error in
            XCTAssertEqual(error as? FileNameValidator.ValidationError, .duplicateName("Existing.txt"))
        }
    }


    func testRejectsCaseFoldedDuplicateNameOnCaseInsensitiveVolumes() throws {
        let directory = try makeTemporaryDirectory()
        let existingURL = directory.appendingPathComponent("Existing.txt")
        try Data().write(to: existingURL)
        let isCaseSensitive = try directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames ?? true

        guard !isCaseSensitive else {
            throw XCTSkip("Case-folded duplicate validation only applies on case-insensitive volumes.")
        }

        XCTAssertThrowsError(try FileNameValidator.validate("existing.txt", in: directory)) { error in
            XCTAssertEqual(error as? FileNameValidator.ValidationError, .duplicateName("Existing.txt"))
        }
    }

    func testAllowsReplacingTheSameItemDuringRename() throws {
        let directory = try makeTemporaryDirectory()
        let existingURL = directory.appendingPathComponent("Existing.txt")
        try Data().write(to: existingURL)

        XCTAssertEqual(
            try FileNameValidator.validate("Existing.txt", in: directory, replacing: existingURL),
            "Existing.txt"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

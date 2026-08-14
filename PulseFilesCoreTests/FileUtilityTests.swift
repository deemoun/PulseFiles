import XCTest
@testable import PulseFilesModels
@testable import PulseFilesUtilities

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

final class FilePathComparisonTests: XCTestCase {
    func testRecognizesSamePathAfterStandardization() {
        let root = URL(fileURLWithPath: "/tmp/PulseFiles")
        let candidate = root.appendingPathComponent("Nested/../Folder")
        let folder = root.appendingPathComponent("Folder")

        XCTAssertTrue(FilePathComparison.isSamePath(candidate, folder))
    }

    func testRecognizesDescendantButNotSiblingPrefix() {
        let source = URL(fileURLWithPath: "/tmp/PulseFiles/Folder", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let siblingWithSharedPrefix = URL(fileURLWithPath: "/tmp/PulseFiles/Folder Backup", isDirectory: true)

        XCTAssertTrue(FilePathComparison.isSameOrDescendant(source, ofDirectory: source))
        XCTAssertTrue(FilePathComparison.isSameOrDescendant(child, ofDirectory: source))
        XCTAssertFalse(FilePathComparison.isSameOrDescendant(siblingWithSharedPrefix, ofDirectory: source))
    }

    func testFindsSelectedDirectoryContainingTransferDestination() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Selected", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let file = root.appendingPathComponent("Selected.txt")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data().write(to: file)

        XCTAssertEqual(
            FilePathComparison.firstDirectoryContaining(source, among: [source, file]),
            source
        )
        XCTAssertEqual(
            FilePathComparison.firstDirectoryContaining(child, among: [source, file]),
            source
        )
    }

    func testDoesNotTreatFilesOrSiblingPrefixAsContainingTransferDestination() throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Selected", isDirectory: true)
        let sibling = root.appendingPathComponent("Selected Backup", isDirectory: true)
        let similarlyNamedFile = root.appendingPathComponent("Selected.txt")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data().write(to: similarlyNamedFile)

        XCTAssertNil(FilePathComparison.firstDirectoryContaining(sibling, among: [source]))
        XCTAssertNil(FilePathComparison.firstDirectoryContaining(sibling, among: [similarlyNamedFile]))
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

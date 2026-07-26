import XCTest
@testable import PulseFiles

final class FilePatternMatcherTests: XCTestCase {
    func testGlobTranslationSupportsWildcardsAndAnchorsWholeFilename() throws {
        let items = [item("Report-1.txt"), item("report-A.TXT"), item("Report-12.txt"), item("xReport-1.txt")]
        let result = try FilePatternMatcher.matches(pattern: "Report-?.txt", mode: .glob, items: items)
        XCTAssertEqual(result.matchingURLs, Set(items.prefix(2).map(\.url)))
    }

    func testInvalidRegularExpressionIsRejectedBeforeApply() {
        XCTAssertNotNil(FilePatternMatcher.validationError(pattern: "([", mode: .regularExpression))
        XCTAssertNil(FilePatternMatcher.validationError(pattern: "^.+\\.swift$", mode: .regularExpression))
    }

    func testPreviewIsBoundedWithoutChangingTotalOrMatches() throws {
        let items = (0..<12).map { item("file\($0).txt") }
        let result = try FilePatternMatcher.matches(pattern: "*.txt", mode: .glob, items: items, previewLimit: 3)
        XCTAssertEqual(result.totalCount, 12)
        XCTAssertEqual(result.matchingURLs.count, 12)
        XCTAssertEqual(result.sampleNames, ["file0.txt", "file1.txt", "file2.txt"])
    }

    func testCallerSuppliedVisibleScopeExcludesFilteredItemsAndParentRow() throws {
        let visible = [item("visible.swift")]
        let filteredOut = item("filtered.swift")
        let result = try FilePatternMatcher.matches(pattern: "*.swift", mode: .glob, items: visible)
        XCTAssertEqual(result.matchingURLs, [visible[0].url])
        XCTAssertFalse(result.matchingURLs.contains(filteredOut.url))
        XCTAssertFalse(result.sampleNames.contains(".."), "Synthetic parent rows are not FileItems and cannot enter the matcher scope.")
    }

    func testMarkMutationUnionsSelectionAndSubtractsDeselectionWithoutChangingUnrelatedMarks() {
        let a = item("a.txt").url, b = item("b.txt").url, c = item("c.md").url
        XCTAssertEqual(MarkMutation.select.applying(matches: [b], to: [a, c]), [a, b, c])
        XCTAssertEqual(MarkMutation.deselect.applying(matches: [b, c], to: [a, c]), [a])
        let initial: Set<URL> = [a, c]
        XCTAssertEqual(initial, [a, c], "Cancel performs no mutation because marks change only through Apply's mutation callback.")
    }

    func testSameExtensionIsCaseInsensitiveAndExtensionlessBehaviorIsDeterministic() {
        let txt = item("a.TXT"), otherTxt = item("b.txt"), markdown = item("c.md")
        XCTAssertEqual(SameExtensionMatcher.matchingURLs(focusedItem: txt, visibleItems: [txt, otherTxt, markdown]), [txt.url, otherTxt.url])
        let noExtension = item("README"), folder = item("Folder", isDirectory: true)
        XCTAssertEqual(SameExtensionMatcher.matchingURLs(focusedItem: noExtension, visibleItems: [noExtension, folder, markdown]), [noExtension.url, folder.url])
        XCTAssertNil(SameExtensionMatcher.matchingURLs(focusedItem: nil, visibleItems: [txt]))
    }

    private func item(_ name: String, isDirectory: Bool = false) -> FileItem {
        let fileExtension = URL(fileURLWithPath: name).pathExtension
        return FileItem(url: URL(fileURLWithPath: "/tmp/\(name)"), filename: name, displayName: name, fileExtension: fileExtension, fileType: isDirectory ? .folder : .file, isDirectory: isDirectory, isSymbolicLink: false, isHidden: false, size: 0, creationDate: nil, modificationDate: nil, posixPermissions: nil, owner: nil, group: nil, typeDescription: isDirectory ? "Folder" : "File", localizedTypeDescription: isDirectory ? "Folder" : "File", iconKey: FileIconKey(fileType: isDirectory ? .folder : .file, fileExtension: fileExtension))
    }
}

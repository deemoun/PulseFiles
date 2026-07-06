import Foundation
import XCTest
@testable import PulseFiles

@MainActor
/// Logic-backed file-pane robot for the SwiftPM unit test target.
///
/// Methods exercise `FilePaneViewModel` directly today, while preserving names
/// that a future UI-backed `FilePanePage` can implement with `XCUIElement`.
final class FilePaneRobot: FilePanePageObject {
    let paneID: PaneID
    let viewModel: FilePaneViewModel
    private(set) var selectedURLs: Set<URL> = []
    private(set) var isActive = false
    private(set) var isVisible = true

    init(paneID: PaneID, viewModel: FilePaneViewModel, isActive: Bool = false) {
        self.paneID = paneID
        self.viewModel = viewModel
        self.isActive = isActive
    }

    @discardableResult
    func markActive(_ active: Bool = true) -> Self {
        isActive = active
        return self
    }

    @discardableResult
    func navigate(to url: URL) -> Self {
        viewModel.navigate(to: url)
        return self
    }

    @discardableResult
    func goParent() -> Self {
        viewModel.goParent()
        return self
    }

    @discardableResult
    func sort(by key: FileSortKey, ascending: Bool) -> Self {
        viewModel.setSort(key, ascending: ascending)
        return self
    }

    @discardableResult
    func filter(_ query: String) -> Self {
        viewModel.setSearchQuery(query)
        return self
    }

    @discardableResult
    func select(_ urls: [URL]) -> Self {
        selectedURLs = Set(urls)
        return self
    }

    @discardableResult
    func expectVisible(_ expected: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(isVisible, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectCurrentDirectory(_ expected: URL, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(viewModel.currentDirectory, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectSelected(_ expected: Set<URL>, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(selectedURLs, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectVisibleItemNames(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(viewModel.visibleItems.map(\.displayName), expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectSort(_ expected: FileSortDescriptor, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(viewModel.sortDescriptor, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectFilter(_ expected: String, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(viewModel.searchQuery, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectActive(_ expected: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(isActive, expected, file: file, line: line)
        return self
    }
}

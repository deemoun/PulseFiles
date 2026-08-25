import XCTest
@testable import PulseFiles
@testable import PulseFilesPane

final class FilePaneContextMenuProviderTests: XCTestCase {
    func testParentContextMapsToParentCommand() {
        XCTAssertEqual(FilePaneContextMenuProvider.entries(for: .parent).compactMap(\.command), [.parent])
    }

    func testBackgroundContextMapsSelectionAndCreationCommands() {
        let commands = FilePaneContextMenuProvider.entries(for: .background(showsHiddenFiles: false)).compactMap(\.command)
        XCTAssertTrue(commands.contains(.newFile))
        XCTAssertTrue(commands.contains(.selectByPattern))
        XCTAssertTrue(commands.contains(.toggleHiddenFiles))
    }
}

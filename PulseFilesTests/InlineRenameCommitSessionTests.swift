import XCTest
@testable import PulseFiles

final class InlineRenameCommitSessionTests: XCTestCase {
    func testReturnThenObjectValueAndEndEditingSubmitsRenameOnce() {
        let fileURL = URL(fileURLWithPath: "/tmp/Original.txt")
        var session = InlineRenameCommitSession()
        session.begin(for: fileURL)
        let generation = try! XCTUnwrap(session.generation(for: fileURL))

        var renameCallbacks = [String]()
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Renamed.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Renamed.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Renamed.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)

        XCTAssertEqual(renameCallbacks, ["Renamed.txt"])
    }

    func testClickAwayObjectValueThenEndEditingSubmitsRenameOnce() {
        let fileURL = URL(fileURLWithPath: "/tmp/Original.txt")
        var session = InlineRenameCommitSession()
        session.begin(for: fileURL)
        let generation = try! XCTUnwrap(session.generation(for: fileURL))

        var renameCallbacks = [String]()
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Renamed.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Renamed.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)

        XCTAssertEqual(renameCallbacks, ["Renamed.txt"])
    }

    func testUnchangedNameConsumesSessionWithoutRename() {
        let fileURL = URL(fileURLWithPath: "/tmp/Original.txt")
        var session = InlineRenameCommitSession()
        session.begin(for: fileURL)
        let generation = try! XCTUnwrap(session.generation(for: fileURL))

        var renameCallbacks = [String]()
        submit(session.commit(itemURL: fileURL, generation: generation, proposedName: "Original.txt", originalName: "Original.txt", isCancelled: false), into: &renameCallbacks)

        XCTAssertTrue(renameCallbacks.isEmpty)
        XCTAssertNil(session.generation(for: fileURL))
    }

    private func submit(_ result: InlineRenameCommitSession.Result, into callbacks: inout [String]) {
        if case let .rename(_, name) = result {
            callbacks.append(name)
        }
    }
}

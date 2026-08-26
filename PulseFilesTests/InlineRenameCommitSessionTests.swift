// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles
@testable import PulseFilesPane

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

    func testExternalRefreshDuringInlineRenameDefersUntilTheEditFinishes() {
        let decision = InlineRenameReloadPolicy.decision(isEditing: true, itemExists: true)

        XCTAssertEqual(decision, .deferReload)
    }

    func testExternalRefreshCancelsInsteadOfRenamingAnItemRemovedExternally() {
        let decision = InlineRenameReloadPolicy.decision(isEditing: true, itemExists: false)

        XCTAssertEqual(decision, .cancelRenameAndReload)
    }

    func testSessionMatchesEquivalentNormalizedURLs() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/PulseFilesRename/../Original.txt")
        let normalizedURL = URL(fileURLWithPath: "/tmp/Original.txt")
        var session = InlineRenameCommitSession()
        session.begin(for: fileURL)

        XCTAssertNotNil(session.generation(for: normalizedURL))
    }

    private func submit(_ result: InlineRenameCommitSession.Result, into callbacks: inout [String]) {
        if case let .rename(_, name) = result {
            callbacks.append(name)
        }
    }
}

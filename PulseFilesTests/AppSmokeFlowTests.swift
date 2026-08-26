// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest
@testable import PulseFiles

@MainActor
final class AppSmokeFlowTests: XCTestCase {
    func testSmokeFlowsStayLogicBackedBecauseSwiftPMDoesNotProvideReliableAppKitXCUITestRunner() async throws {
        let app = try AppRobot.temporary()
        let leftDirectory = app.leftPane.viewModel.currentDirectory
        let rightDirectory = app.rightPane.viewModel.currentDirectory

        app.fileSystem.setItems([
            TestFileSystem.item(named: "alpha.txt", in: leftDirectory),
            TestFileSystem.item(named: "beta.md", in: leftDirectory),
            TestFileSystem.item(named: "Reports", in: leftDirectory, isDirectory: true)
        ], for: leftDirectory)
        app.fileSystem.setItems([
            TestFileSystem.item(named: "right-pane.txt", in: rightDirectory)
        ], for: rightDirectory)

        let launchedApp = await app.launch()
        launchedApp
            .expectLaunched()
            .expectPanesVisible()
            .expectAccessibilityIdentifiers()
            .expectActivePane(.left)
            .switchPane()
            .expectActivePane(.right)
            .switchPane()
            .expectActivePane(.left)
            .toggleSidebar()
            .expectSidebarVisible(false)
            .toggleSidebar()
            .expectSidebarVisible(true)

        app.rightPane
            .expectAccessibilityIdentifiers()

        XCTAssertEqual(app.commandBar.fieldAccessibilityIdentifier, AccessibilityIdentifiers.CommandBar.field)
        XCTAssertEqual(app.commandBar.listAccessibilityIdentifier, AccessibilityIdentifiers.CommandBar.list)
        XCTAssertEqual(app.sidebar.toggleAccessibilityIdentifier, AccessibilityIdentifiers.Toolbar.sidebarToggle)
        XCTAssertEqual(app.sidebar.listAccessibilityIdentifier, AccessibilityIdentifiers.Sidebar.list)
        XCTAssertEqual(app.terminal.panelAccessibilityIdentifier, AccessibilityIdentifiers.Terminal.panel)
        XCTAssertEqual(app.terminal.toggleAccessibilityIdentifier, AccessibilityIdentifiers.Toolbar.terminalToggle)

        app.leftPane
            .filter("alpha")
            .expectFilter("alpha")
            .expectVisibleItemNames(["alpha.txt"])

        app.commandBar
            .open()
            .expectOpen(true)
            .expectIntrinsicWidthLayoutPriorities()
            .expectLocalizedTooltips()
            .expectDestructiveTreatment()
            .typeKnownCommand(.view)
            .expectExecuted([.open])

        app.terminal
            .expectEnabled(false)
            .expectVisibleByDefault(false)

        let progressDialog = FileOperationProgressRobot()
        progressDialog.start(operationName: "Copying")
        progressDialog.update(
            operationName: "Copying",
            progress: FileOperationProgress(
                currentItemName: "alpha.txt",
                completedCount: 1,
                totalCount: 2,
                completedByteCount: 512,
                totalByteCount: 1024
            )
        )
        XCTAssertEqual(progressDialog.dialogAccessibilityIdentifier, AccessibilityIdentifiers.FileOperationProgress.dialog)
        XCTAssertEqual(progressDialog.progressAccessibilityIdentifier, AccessibilityIdentifiers.FileOperationProgress.indicator)
        XCTAssertEqual(progressDialog.currentItemAccessibilityIdentifier, AccessibilityIdentifiers.FileOperationProgress.currentItemLabel)
        XCTAssertEqual(progressDialog.detailAccessibilityIdentifier, AccessibilityIdentifiers.FileOperationProgress.detailLabel)
        XCTAssertEqual(progressDialog.cancelAccessibilityIdentifier, AccessibilityIdentifiers.FileOperationProgress.cancelButton)
        XCTAssertFalse(progressDialog.presentation?.isIndeterminate ?? true)
        progressDialog.cancel()
        progressDialog.expectVisible(true).expectCancellationPending()
        progressDialog.finish()
        progressDialog.expectVisible(false)

        app.leftPane.select([leftDirectory.appendingPathComponent("alpha.txt")])
        app.requestDestructiveCommand(.trash)
            .expectPendingDestructiveConfirmation(.trash)
            .expectDestructiveMutationCount(0)
    }

    func testFileClipboardReadsFinderStyleFileURLsAsCopy() throws {
        let pasteboard = makeFileClipboardPasteboard()
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let urls = [
            URL(fileURLWithPath: "/tmp/PulseFiles/alpha.txt"),
            URL(fileURLWithPath: "/tmp/PulseFiles/beta.txt")
        ]

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects(urls as [NSURL]))

        XCTAssertEqual(clipboard.read(), FileClipboard.Payload(urls: urls, operation: .copy))
    }

    func testFileClipboardReadsPulseFilesCopyInput() throws {
        let pasteboard = makeFileClipboardPasteboard()
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let urls = [URL(fileURLWithPath: "/tmp/PulseFiles/alpha.txt")]

        clipboard.write(urls: urls, operation: .copy)

        XCTAssertEqual(clipboard.read(), FileClipboard.Payload(urls: urls, operation: .copy))
    }

    func testFileClipboardReadsPulseFilesCutInput() throws {
        let pasteboard = makeFileClipboardPasteboard()
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let urls = [URL(fileURLWithPath: "/tmp/PulseFiles/alpha.txt")]

        clipboard.write(urls: urls, operation: .move)

        XCTAssertEqual(clipboard.read(), FileClipboard.Payload(urls: urls, operation: .move))
        XCTAssertGreaterThan(clipboard.changeCount, 0)
    }

    func testFileClipboardReturnsNilForEmptyPasteboard() throws {
        let pasteboard = makeFileClipboardPasteboard()
        let clipboard = FileClipboard(pasteboard: pasteboard)

        pasteboard.clearContents()

        XCTAssertNil(clipboard.read())
    }

    func testFileClipboardIgnoresMixedInvalidPasteboardEntries() throws {
        let pasteboard = makeFileClipboardPasteboard()
        let clipboard = FileClipboard(pasteboard: pasteboard)
        let fileURL = URL(fileURLWithPath: "/tmp/PulseFiles/alpha.txt")
        let webURL = URL(string: "https://example.com/alpha.txt")!

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL, webURL as NSURL, "not a URL" as NSString]))

        XCTAssertEqual(clipboard.read(), FileClipboard.Payload(urls: [fileURL], operation: .copy))
    }

    private func makeFileClipboardPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PulseFilesTests.FileClipboard.\(UUID().uuidString)"))
    }
}

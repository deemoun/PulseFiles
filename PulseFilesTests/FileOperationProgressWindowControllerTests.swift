// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class FileOperationProgressWindowControllerTests: XCTestCase {
    func testDeterminatePresentationFormatsCountsAndBytes() {
        let presentation = FileOperationProgressPresentation.make(
            operationName: "Copying",
            progress: FileOperationProgress(
                currentItemName: "report.pdf",
                completedCount: 2,
                totalCount: 4,
                completedByteCount: 512,
                totalByteCount: 1024
            )
        )

        XCTAssertEqual(presentation.title, "Copying")
        XCTAssertEqual(presentation.currentItemName, "report.pdf")
        XCTAssertEqual(presentation.itemCountDetail, "2/4 items")
        XCTAssertFalse(presentation.isIndeterminate)
        XCTAssertEqual(presentation.progressValue, 0.5)
        XCTAssertFalse(presentation.byteCountDetail.isEmpty)
    }

    func testPreparingAndCancellationPresentationsAreIndeterminate() {
        let preparing = FileOperationProgressPresentation.make(
            operationName: "Moving",
            progress: FileOperationProgress(currentItemName: "folder", completedCount: 0, totalCount: 1, isPreparingTransfer: true)
        )
        let cancelling = FileOperationProgressPresentation.make(operationName: "Moving", progress: nil, isCancellationPending: true)

        XCTAssertTrue(preparing.isIndeterminate)
        XCTAssertEqual(preparing.itemCountDetail, "Preparing transfer…")
        XCTAssertTrue(cancelling.isIndeterminate)
        XCTAssertTrue(cancelling.isCancellationPending)
        XCTAssertEqual(cancelling.itemCountDetail, "Cancelling operation…")
    }

    func testUnknownResultRequiresVerificationRatherThanReportingCancellation() {
        let result = FileOperationResult.unknownAfterAbandoning()

        XCTAssertTrue(result.needsVerification)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.succeededCompletely)
        let presentation = FileOperationCoordinator.resultPresentation(result, operationName: "Copy")
        XCTAssertEqual(presentation?.message, "Copy Needs Verification")
        XCTAssertTrue(presentation?.detail.contains("final filesystem state is unknown") == true)
    }
}

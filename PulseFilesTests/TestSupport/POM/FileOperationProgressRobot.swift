// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import PulseFiles

@MainActor
/// Logic-backed representation of the non-blocking operation progress dialog.
final class FileOperationProgressRobot {
    private(set) var isVisible = false
    private(set) var presentation: FileOperationProgressPresentation?
    private(set) var cancellationRequested = false

    var dialogAccessibilityIdentifier: String { AccessibilityIdentifiers.FileOperationProgress.dialog }
    var progressAccessibilityIdentifier: String { AccessibilityIdentifiers.FileOperationProgress.indicator }
    var currentItemAccessibilityIdentifier: String { AccessibilityIdentifiers.FileOperationProgress.currentItemLabel }
    var detailAccessibilityIdentifier: String { AccessibilityIdentifiers.FileOperationProgress.detailLabel }
    var cancelAccessibilityIdentifier: String { AccessibilityIdentifiers.FileOperationProgress.cancelButton }

    func start(operationName: String) {
        isVisible = true
        presentation = FileOperationProgressPresentation.make(operationName: operationName, progress: nil)
    }

    func update(operationName: String, progress: FileOperationProgress) {
        presentation = FileOperationProgressPresentation.make(operationName: operationName, progress: progress)
    }

    func cancel() {
        cancellationRequested = true
        guard let presentation else { return }
        self.presentation = FileOperationProgressPresentation.make(
            operationName: presentation.title,
            progress: nil,
            isCancellationPending: true
        )
    }

    func finish() { isVisible = false }

    @discardableResult
    func expectVisible(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertEqual(isVisible, expected, file: file, line: line)
        return self
    }

    @discardableResult
    func expectCancellationPending(file: StaticString = #filePath, line: UInt = #line) -> Self {
        XCTAssertTrue(presentation?.isCancellationPending == true, file: file, line: line)
        XCTAssertTrue(cancellationRequested, file: file, line: line)
        return self
    }
}

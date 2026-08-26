// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class DiagnosticsExportServiceTests: XCTestCase {
    func testRedactorExcludesSensitiveCategoriesValuesAndPaths() {
        XCTAssertEqual(DiagnosticsRedactor.redactEntry(category: "Terminal", message: "rm -rf /Users/alice/private"), "[excluded by redaction policy]")
        let redacted = DiagnosticsRedactor.redact("token: abc123\nOpened /Users/alice/Documents/report.txt")
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("/Users/alice/Documents/report.txt"))
        XCTAssertTrue(redacted.contains("[redacted]"))
        XCTAssertTrue(redacted.contains("[redacted-path]"))
    }

    func testExportWritesDocumentedSanitizedContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = DiagnosticsExportService(
            dateProvider: { date },
            appInfoProvider: { .init(name: "PulseFiles", version: "2.0", build: "42", macOSVersion: "macOS Test") }
        )
        let entry = DiagnosticLogEntry(id: UUID(), timestamp: date, level: .error, category: "FileOperation", message: "password: not-safe\nFailed at /Users/alice/secret.txt")
        let summary = DiagnosticOperationSummary(operation: "Copy", result: .init(completedItems: [], skippedItems: [], failedItems: [], cleanupWarnings: [], wasCancelled: false, needsVerification: true))

        let bundle = try service.export(to: directory, entries: [entry], operationSummaries: [summary])
        let diagnostics = try String(contentsOf: bundle.appendingPathComponent("diagnostics.txt"), encoding: .utf8)
        let policy = try String(contentsOf: bundle.appendingPathComponent("REDACTION_POLICY.txt"), encoding: .utf8)

        XCTAssertTrue(diagnostics.contains("Version: 2.0"))
        XCTAssertTrue(diagnostics.contains("Build: 42"))
        XCTAssertTrue(diagnostics.contains("macOS: macOS Test"))
        XCTAssertTrue(diagnostics.contains("operation=Copy; completed=0"))
        XCTAssertTrue(diagnostics.contains("needsVerification=true"))
        XCTAssertFalse(diagnostics.contains("not-safe"))
        XCTAssertFalse(diagnostics.contains("/Users/alice/secret.txt"))
        XCTAssertTrue(policy.contains("does not automatically collect or upload"))
        XCTAssertTrue(policy.contains("security-scoped bookmark data"))
    }
}

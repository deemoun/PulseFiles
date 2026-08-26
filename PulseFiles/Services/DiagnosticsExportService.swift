// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

/// Creates an on-demand, local-only support bundle. Nothing is collected, retained,
/// or uploaded until a person explicitly chooses Export Diagnostics.
package struct DiagnosticOperationSummary: Equatable {
    package let operation: String
    package let completedCount: Int
    package let skippedCount: Int
    package let failedCount: Int
    package let cleanupWarningCount: Int
    package let wasCancelled: Bool
    package let needsVerification: Bool

    package init(operation: String, result: FileOperationResult) {
        self.operation = operation
        completedCount = result.completedItems.count
        skippedCount = result.skippedItems.count
        failedCount = result.failedItems.count
        cleanupWarningCount = result.cleanupWarnings.count
        wasCancelled = result.wasCancelled
        needsVerification = result.needsVerification
    }
}

package struct DiagnosticsExportService {
    package struct AppInfo: Equatable {
        let name: String
        let version: String
        let build: String
        let macOSVersion: String
    }

    package static let redactionPolicy = """
    Redaction policy
    ================
    This bundle is created only when you choose Export Diagnostics. PulseFiles does not automatically collect or upload diagnostics.

    Included: app version/build, macOS version, sanitized in-memory diagnostic entries, and count-only summaries of recent file-operation results.
    Excluded: filesystem paths, security-scoped bookmark data, clipboard contents, terminal commands, terminal output, and values associated with passwords, tokens, secrets, credentials, authorization, or API keys.
    Diagnostic entries from Terminal, Clipboard, or Bookmark categories are excluded entirely. Other diagnostic text has sensitive key/value values and path-like text replaced with [redacted]. Review this bundle before sharing it.
    """

    package let fileManager: FileManager
    package let dateProvider: () -> Date
    package let appInfoProvider: () -> AppInfo

    package init(
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        appInfoProvider: @escaping () -> AppInfo = Self.currentAppInfo
    ) {
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.appInfoProvider = appInfoProvider
    }

    package func export(to parentDirectory: URL, entries: [DiagnosticLogEntry], operationSummaries: [DiagnosticOperationSummary]) throws -> URL {
        let bundleURL = parentDirectory.appendingPathComponent("PulseFiles-Diagnostics-\(Self.timestamp(dateProvider()))", isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: false)
        try renderedDiagnostics(entries: entries, operationSummaries: operationSummaries)
            .write(to: bundleURL.appendingPathComponent("diagnostics.txt"), atomically: true, encoding: .utf8)
        try Self.redactionPolicy.write(to: bundleURL.appendingPathComponent("REDACTION_POLICY.txt"), atomically: true, encoding: .utf8)
        return bundleURL
    }

    package func renderedDiagnostics(entries: [DiagnosticLogEntry], operationSummaries: [DiagnosticOperationSummary]) -> String {
        let info = appInfoProvider()
        var lines = [
            "PulseFiles Diagnostics",
            "Generated: \(Self.iso8601.string(from: dateProvider()))",
            "App: \(DiagnosticsRedactor.redact(info.name))",
            "Version: \(DiagnosticsRedactor.redact(info.version))",
            "Build: \(DiagnosticsRedactor.redact(info.build))",
            "macOS: \(DiagnosticsRedactor.redact(info.macOSVersion))",
            "",
            "Operation result summaries (counts only):"
        ]
        if operationSummaries.isEmpty { lines.append("(none recorded in this app session)") }
        lines += operationSummaries.map { summary in
            "operation=\(DiagnosticsRedactor.redact(summary.operation)); completed=\(summary.completedCount); skipped=\(summary.skippedCount); failed=\(summary.failedCount); cleanupWarnings=\(summary.cleanupWarningCount); cancelled=\(summary.wasCancelled); needsVerification=\(summary.needsVerification)"
        }
        lines += ["", "Sanitized in-memory diagnostics:"]
        if entries.isEmpty { lines.append("(none recorded in this app session)") }
        lines += entries.map { entry in
            let category = DiagnosticsRedactor.redactCategory(entry.category)
            let message = DiagnosticsRedactor.redactEntry(category: entry.category, message: entry.message)
            return "\(Self.iso8601.string(from: entry.timestamp)) [\(entry.level.rawValue.uppercased())] \(category): \(message)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func currentAppInfo() -> AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            name: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "PulseFiles",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

package enum DiagnosticsRedactor {
    private static let excludedCategories = ["terminal", "clipboard", "bookmark"]
    private static let sensitiveKeys = ["api_key", "apikey", "authorization", "bearer", "credential", "password", "secret", "token"]

    package static func redactCategory(_ category: String) -> String {
        excludedCategories.contains { category.localizedCaseInsensitiveContains($0) } ? "[redacted category]" : redact(category)
    }

    package static func redactEntry(category: String, message: String) -> String {
        guard !excludedCategories.contains(where: { category.localizedCaseInsensitiveContains($0) }) else {
            return "[excluded by redaction policy]"
        }
        return redact(message)
    }

    package static func redact(_ value: String) -> String {
        var result = value
        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = line[..<separator].lowercased()
            if sensitiveKeys.contains(where: { key.contains($0) }) {
                result = result.replacingOccurrences(of: String(line), with: "\(line[..<separator])\(line[separator]) [redacted]")
            }
        }
        // URLs and absolute/home-relative paths can identify files or people.
        result = result.replacingOccurrences(of: #"file://[^\s]+|(?:^|\s)(?:/|~/)[^\s]+"#, with: " [redacted-path]", options: .regularExpression)
        return result
    }
}

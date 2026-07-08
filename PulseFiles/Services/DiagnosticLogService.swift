import Foundation

struct DiagnosticLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: DiagnosticLogLevel
    let category: String
    let message: String
}

enum DiagnosticLogLevel: String, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    static func < (lhs: DiagnosticLogLevel, rhs: DiagnosticLogLevel) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

@MainActor
final class DiagnosticLogService {
    static let shared = DiagnosticLogService()
    static let entriesDidChangeNotification = Notification.Name("DiagnosticLogServiceEntriesDidChange")

    private static let maximumMessageLength = 2_000
    private static let redactedValue = "[redacted]"
    private static let sensitiveKeyFragments = [
        "api_key",
        "apikey",
        "authorization",
        "bearer",
        "credential",
        "password",
        "secret",
        "token"
    ]

    private let maximumEntryCount: Int
    private var dateProvider: () -> Date
    private var idProvider: () -> UUID

    private(set) var entries: [DiagnosticLogEntry] = []

    init(
        maximumEntryCount: Int = 750,
        dateProvider: @escaping () -> Date = Date.init,
        idProvider: @escaping () -> UUID = UUID.init
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.dateProvider = dateProvider
        self.idProvider = idProvider
    }

    func log(_ level: DiagnosticLogLevel, category: String, _ message: String) {
        let entry = DiagnosticLogEntry(
            id: idProvider(),
            timestamp: dateProvider(),
            level: level,
            category: sanitizedCategory(category),
            message: sanitizedMessage(message)
        )
        entries.append(entry)
        trimEntriesIfNeeded()
        postEntriesDidChangeNotification()
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        postEntriesDidChangeNotification()
    }

    private func postEntriesDidChangeNotification() {
        NotificationCenter.default.post(name: Self.entriesDidChangeNotification, object: self)
    }

    private func trimEntriesIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        entries.removeFirst(entries.count - maximumEntryCount)
    }

    private func sanitizedCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General" : String(trimmed.prefix(80))
    }

    private func sanitizedMessage(_ message: String) -> String {
        var sanitized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = redactingSensitiveKeyValuePairs(in: sanitized)
        if sanitized.count > Self.maximumMessageLength {
            let endIndex = sanitized.index(sanitized.startIndex, offsetBy: Self.maximumMessageLength)
            sanitized = String(sanitized[..<endIndex]) + "… [truncated]"
        }
        return sanitized
    }

    private func redactingSensitiveKeyValuePairs(in message: String) -> String {
        message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let separatorIndex = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                    return String(line)
                }
                let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard Self.sensitiveKeyFragments.contains(where: { key.contains($0) }) else {
                    return String(line)
                }
                return "\(line[..<separatorIndex])\(line[separatorIndex]) \(Self.redactedValue)"
            }
            .joined(separator: "\n")
    }
}


enum DiagnosticLogger {
    static func log(_ level: DiagnosticLogLevel, category: String, _ message: String) {
        Task { @MainActor in
            DiagnosticLogService.shared.log(level, category: category, message)
        }
    }

    static func sanitizedPath(_ url: URL) -> String {
        let standardizedPath = url.standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if standardizedPath == homePath {
            return "~"
        }
        if standardizedPath.hasPrefix(homePath + "/") {
            return "~/" + String(standardizedPath.dropFirst(homePath.count + 1))
        }
        let sandboxPath = ExperimentalFlags.appSandboxRoot.standardizedFileURL.path
        if standardizedPath == sandboxPath {
            return "[sandbox-root]"
        }
        if standardizedPath.hasPrefix(sandboxPath + "/") {
            return "[sandbox-root]/" + String(standardizedPath.dropFirst(sandboxPath.count + 1))
        }
        return url.lastPathComponent.isEmpty ? standardizedPath : "…/\(url.lastPathComponent)"
    }
}

import XCTest
@testable import PulseFiles

@MainActor
final class DiagnosticLogServiceTests: XCTestCase {
    func testLogRecordsEntryMetadata() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let date = Date(timeIntervalSince1970: 42)
        let service = DiagnosticLogService(
            maximumEntryCount: 10,
            dateProvider: { date },
            idProvider: { id }
        )

        service.log(.info, category: "Navigation", "Opened folder")

        XCTAssertEqual(service.entries, [
            DiagnosticLogEntry(
                id: id,
                timestamp: date,
                level: .info,
                category: "Navigation",
                message: "Opened folder"
            )
        ])
    }

    func testLogKeepsMostRecentEntriesWithinBound() {
        var counter = 0
        let service = DiagnosticLogService(maximumEntryCount: 3, idProvider: {
            counter += 1
            return UUID(uuidString: "00000000-0000-0000-0000-00000000000\(counter)")!
        })

        service.log(.debug, category: "Test", "one")
        service.log(.debug, category: "Test", "two")
        service.log(.debug, category: "Test", "three")
        service.log(.debug, category: "Test", "four")

        XCTAssertEqual(service.entries.map(\.message), ["two", "three", "four"])
    }

    func testClearRemovesEntries() {
        let service = DiagnosticLogService(maximumEntryCount: 3)
        service.log(.warning, category: "Test", "Something happened")

        service.clear()

        XCTAssertTrue(service.entries.isEmpty)
    }

    func testLogSanitizesCategoryMessageAndSensitiveValues() {
        let service = DiagnosticLogService(maximumEntryCount: 3)
        let longMessage = String(repeating: "x", count: 2_050)

        service.log(.error, category: "   ", "password: hunter2\n\(longMessage)")

        XCTAssertEqual(service.entries.first?.category, "General")
        XCTAssertFalse(service.entries.first?.message.contains("hunter2") ?? true)
        XCTAssertTrue(service.entries.first?.message.contains("password: [redacted]") ?? false)
        XCTAssertTrue(service.entries.first?.message.hasSuffix("… [truncated]") ?? false)
    }
}

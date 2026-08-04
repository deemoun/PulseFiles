import XCTest
@testable import PulseFiles

final class FileOperationComponentTests: XCTestCase {
    func testKeepBothPlannerSkipsReservedAndExistingNames() {
        let destination = URL(fileURLWithPath: "/tmp/report.txt")
        let reserved = Set([FilePathComparison.normalizedPath(URL(fileURLWithPath: "/tmp/report copy.txt"))])
        let result = FileTransferPlanner.keepBothDestination(for: destination, reservedDestinations: reserved) { $0.lastPathComponent == "report copy 2.txt" }
        XCTAssertEqual(result.lastPathComponent, "report copy 3.txt")
    }
}

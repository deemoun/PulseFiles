import XCTest
@testable import PulseFiles

final class VolumeStatusPresentationTests: XCTestCase {
    func testUnknownCapacityUsesUnavailableCapacityLabel() {
        let status = VolumeStatusPresentation(
            volumeURL: URL(fileURLWithPath: "/Volumes/Archive"), localizedName: "Archive",
            availableCapacity: nil, totalCapacity: nil, isReadOnly: false
        )

        XCTAssertEqual(status.label, "Archive — Capacity unavailable")
        XCTAssertFalse(status.isWarning)
    }

    func testReadOnlyMediaUsesWarningTreatment() {
        let status = VolumeStatusPresentation(
            volumeURL: URL(fileURLWithPath: "/Volumes/Installer"), localizedName: "Installer",
            availableCapacity: 5_000_000_000, totalCapacity: 16_000_000_000, isReadOnly: true
        )

        XCTAssertTrue(status.isWarning)
        XCTAssertTrue(status.detail.contains("Read-only"))
    }

    func testExternalVolumeIncludesNameCapacityAndPath() {
        let status = VolumeStatusPresentation(
            volumeURL: URL(fileURLWithPath: "/Volumes/My SSD"), localizedName: "My SSD",
            availableCapacity: 120_000_000_000, totalCapacity: 1_000_000_000_000, isReadOnly: false
        )

        XCTAssertEqual(status.label, "My SSD — 120 GB free of 1 TB")
        XCTAssertEqual(status.locationDescription, "My SSD (/Volumes/My SSD)")
        XCTAssertFalse(status.isWarning)
    }
}

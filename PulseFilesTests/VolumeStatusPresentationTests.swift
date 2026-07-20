import XCTest
@testable import PulseFiles

final class VolumeStatusPresentationTests: XCTestCase {
    @MainActor
    func testStaleResolutionDoesNotReplaceCurrentDirectoryStatus() {
        let firstDirectory = URL(fileURLWithPath: "/Volumes/First")
        let secondDirectory = URL(fileURLWithPath: "/Volumes/Second")
        let cache = VolumeStatusResolutionCache(directory: firstDirectory)
        let firstStatus = VolumeStatusPresentation(volumeURL: firstDirectory, localizedName: "First", availableCapacity: 1, totalCapacity: 2, isReadOnly: false)
        let secondStatus = VolumeStatusPresentation(volumeURL: secondDirectory, localizedName: "Second", availableCapacity: 1, totalCapacity: 2, isReadOnly: false)

        cache.beginResolution(for: firstDirectory, loadGeneration: 1)
        cache.beginResolution(for: secondDirectory, loadGeneration: 2)
        cache.apply(firstStatus, for: firstDirectory, loadGeneration: 1)

        XCTAssertEqual(cache.status, .loading(for: secondDirectory))
        cache.apply(secondStatus, for: secondDirectory, loadGeneration: 2)
        XCTAssertEqual(cache.status, secondStatus)
    }

    func testUnavailableVolumeFallsBackToDirectoryDescription() async {
        let directory = URL(fileURLWithPath: "/definitely-not-a-mounted-volume/PulseFiles")

        let status = await VolumeStatusPresentation.resolve(for: directory)

        XCTAssertEqual(status.availability, .unavailable)
        XCTAssertEqual(status.localizedName, directory.path)
        XCTAssertEqual(status.label, "\(directory.path) — Volume unavailable")
    }

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

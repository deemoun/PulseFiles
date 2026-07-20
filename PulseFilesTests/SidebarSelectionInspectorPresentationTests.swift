import AppKit
import XCTest
@testable import PulseFiles

final class SidebarSelectionInspectorPresentationTests: XCTestCase {
    func testSingleSelectionIncludesFileMetadataRows() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = Date(timeIntervalSince1970: 1_700_100_000)
        let item = fileItem(
            "report.pdf",
            size: 4_096,
            creationDate: created,
            modificationDate: modified,
            permissions: 0o644,
            owner: "alice",
            group: "staff",
            localizedType: "PDF Document"
        )

        let presentation = try XCTUnwrap(SidebarViewController.SelectionInspectorPresentation.make(for: [item]))
        let rows = Dictionary(uniqueKeysWithValues: presentation.rows.map { ($0.title, $0.value) })

        XCTAssertEqual(presentation.title, "report.pdf")
        XCTAssertEqual(presentation.selectedURLs, [item.url])
        XCTAssertEqual(rows["File Size"], FileSizeFormatter.string(fromByteCount: 4_096))
        XCTAssertEqual(rows["Type"], "File")
        XCTAssertEqual(rows["Localized Type"], "PDF Document")
        XCTAssertEqual(rows["Permissions"], "644")
        XCTAssertEqual(rows["Owner"], "alice")
        XCTAssertEqual(rows["Group"], "staff")
        XCTAssertNotNil(rows["Created"])
        XCTAssertNotNil(rows["Modified"])
    }

    func testMultipleSelectionIncludesAggregateCountSizeAndPaths() throws {
        let first = fileItem("one.txt", size: 1_024)
        let second = fileItem("two.txt", size: 2_048)
        let folder = fileItem("Folder", type: .folder, isDirectory: true, size: 0, localizedType: "Folder")

        let presentation = try XCTUnwrap(SidebarViewController.SelectionInspectorPresentation.make(for: [first, second, folder]))
        let rows = Dictionary(uniqueKeysWithValues: presentation.rows.map { ($0.title, $0.value) })

        XCTAssertEqual(presentation.title, "3 items selected")
        XCTAssertEqual(presentation.subtitle, "2 files, 1 folder")
        XCTAssertEqual(presentation.selectedURLs, [first.url, second.url, folder.url])
        XCTAssertEqual(rows["Selected Items"], "3")
        XCTAssertEqual(rows["Selected Size"], FileSizeFormatter.string(fromByteCount: 3_072))
        XCTAssertEqual(rows["Total Space"], "Calculating…")
        XCTAssertEqual(rows["Type"], "Mixed selection")
    }

    func testEmptySelectionHasNoInspectorPresentation() {
        XCTAssertNil(SidebarViewController.SelectionInspectorPresentation.make(for: []))
    }

    func testTotalSizeReturnsFallbackWhenAccessPolicyDeniesDirectory() async throws {
        let deniedDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sandboxRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: deniedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: deniedDirectory)
            try? FileManager.default.removeItem(at: sandboxRoot)
        }

        let child = deniedDirectory.appendingPathComponent("secret.txt")
        try Data(repeating: 1, count: 128).write(to: child)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxRoot)

        let size = await SidebarViewController.totalSize(for: deniedDirectory, fallback: 42, accessPolicy: policy)

        XCTAssertEqual(size, 42)
    }

    func testTotalSizeEnumeratesAllowedDirectory() async throws {
        let sandboxRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        try Data(repeating: 1, count: 128).write(to: sandboxRoot.appendingPathComponent("first.txt"))
        try Data(repeating: 1, count: 64).write(to: sandboxRoot.appendingPathComponent("second.txt"))
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxRoot)

        let size = await SidebarViewController.totalSize(for: sandboxRoot, fallback: 42, accessPolicy: policy)

        XCTAssertEqual(size, 192)
    }

    @MainActor
    func testStaleSelectionDoesNotReceiveLateMetadata() async throws {
        let firstMetadataStarted = expectation(description: "first metadata read started")
        let secondMetadataDisplayed = expectation(description: "second metadata displayed")
        let firstMetadataMayFinish = DispatchSemaphore(value: 0)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sidebar = SidebarViewController(
            recentLocations: RecentLocationService(defaults: defaults),
            metadataReader: { url in
                if url.lastPathComponent == "first.jpg" {
                    firstMetadataStarted.fulfill()
                    firstMetadataMayFinish.wait()
                    return "first location"
                }
                return "second location"
            }
        )
        var updates: [(String, String)] = []
        sidebar.onInspectorDetailUpdate = { identifier, value in
            updates.append((identifier, value))
            if identifier == "gps-location", value == "second location" {
                secondMetadataDisplayed.fulfill()
            }
        }

        _ = sidebar.view
        sidebar.showSelection([fileItem("first.jpg", size: 1)])
        await fulfillment(of: [firstMetadataStarted], timeout: 1)

        sidebar.showSelection([fileItem("second.jpg", size: 1)])
        firstMetadataMayFinish.signal()
        await fulfillment(of: [secondMetadataDisplayed], timeout: 1)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(updates.contains { $0.1 == "first location" })
    }

    @MainActor
    func testMetadataReaderFailureDisplaysNoGPSMetadata() async {
        let missingMetadataDisplayed = expectation(description: "missing metadata displayed")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sidebar = SidebarViewController(
            recentLocations: RecentLocationService(defaults: defaults),
            metadataReader: { _ in throw MetadataReaderError.failed }
        )
        sidebar.onInspectorDetailUpdate = { identifier, value in
            if identifier == "gps-location", value == "No GPS metadata" {
                missingMetadataDisplayed.fulfill()
            }
        }

        _ = sidebar.view
        sidebar.showSelection([fileItem("image.jpg", size: 1)])

        await fulfillment(of: [missingMetadataDisplayed], timeout: 1)
    }

    private func fileItem(
        _ name: String,
        type: FileItemType = .file,
        isDirectory: Bool = false,
        size: Int64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        permissions: Int? = nil,
        owner: String? = nil,
        group: String? = nil,
        localizedType: String = "Plain Text"
    ) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            filename: name,
            displayName: name,
            fileExtension: URL(fileURLWithPath: name).pathExtension,
            fileType: type,
            isDirectory: isDirectory,
            isSymbolicLink: type == .symbolicLink,
            isHidden: name.hasPrefix("."),
            size: size,
            creationDate: creationDate,
            modificationDate: modificationDate,
            posixPermissions: permissions,
            owner: owner,
            group: group,
            typeDescription: localizedType,
            localizedTypeDescription: localizedType,
            iconKey: FileIconKey(fileType: type, fileExtension: URL(fileURLWithPath: name).pathExtension)
        )
    }

    private enum MetadataReaderError: Error {
        case failed
    }
}

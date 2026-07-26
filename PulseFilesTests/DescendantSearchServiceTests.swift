import XCTest
@testable import PulseFiles

final class DescendantSearchServiceTests: XCTestCase {
    func testSearchReportsPathContextAndDoesNotFollowSymbolicLinks() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let nested = try fixture.temporaryDirectory.folder("AllowedSandbox/Allowed/Deep")
        _ = try fixture.temporaryDirectory.file("AllowedSandbox/Allowed/Deep/needle.txt")
        let outside = try fixture.externalFile("secret-needle.txt")
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("outside-link"), withDestinationURL: outside.deletingLastPathComponent())

        let result = try await DescendantSearchService(accessPolicy: fixture.policy).search(query: "needle", rootURL: fixture.allowedDirectory)
        XCTAssertEqual(result.items.map(\.name), ["needle.txt"])
        XCTAssertEqual(result.items.first?.pathContext, nested.path)
        XCTAssertFalse(result.items.contains { $0.url.path.contains("secret-needle") })
    }

    func testSearchHonorsSandboxBoundaryForRoot() async throws {
        let fixture = try SandboxFixture(testCase: self)
        await XCTAssertThrowsErrorAsync(try await DescendantSearchService(accessPolicy: fixture.policy).search(query: "x", rootURL: fixture.externalDirectory))
    }

    func testSearchReportsPolicyDeniedDescendants() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let allowed = try fixture.allowedFile("visible.txt")
        let denied = try fixture.allowedFile("denied.txt")
        let probe = SandboxFileAccessPolicy.AccessProbe(fileExists: { _ in true }, isReadableFile: { $0 != denied.path }, isWritableFile: { _ in true })
        let policy = SandboxFileAccessPolicy(isEnabled: false, rootURL: fixture.root, accessProbe: probe)
        let result = try await DescendantSearchService(accessPolicy: policy).search(query: ".txt", rootURL: fixture.allowedDirectory)
        XCTAssertTrue(result.items.contains { $0.url == allowed })
        XCTAssertTrue(result.inaccessibleURLs.contains(denied))
    }

    func testSearchStopsAtItemAndDepthLimits() async throws {
        let fixture = try SandboxFixture(testCase: self)
        for index in 0..<4 { _ = try fixture.allowedFile("many/item\(index).txt") }
        _ = try fixture.allowedFile("a/b/c/deep.txt")
        let service = DescendantSearchService(accessPolicy: fixture.policy)
        let itemLimited = try await service.search(query: "item", rootURL: fixture.allowedDirectory, limits: .init(maximumItems: 2, maximumDepth: 32, timeout: 5))
        XCTAssertEqual(itemLimited.items.count, 2)
        XCTAssertTrue(itemLimited.hitItemLimit)
        let depthLimited = try await service.search(query: "deep", rootURL: fixture.allowedDirectory, limits: .init(maximumItems: 10, maximumDepth: 1, timeout: 5))
        XCTAssertTrue(depthLimited.hitDepthLimit)
        XCTAssertTrue(depthLimited.items.isEmpty)
    }

    func testCancelledSearchReportsCancellation() async throws {
        let fixture = try SandboxFixture(testCase: self)
        for index in 0..<500 { _ = try fixture.allowedFile("cancel/item\(index).txt") }
        let service = DescendantSearchService(accessPolicy: fixture.policy)
        let task = Task { try await service.search(query: "item", rootURL: fixture.allowedDirectory, limits: .init(maximumItems: 10_000, maximumDepth: 32, timeout: 30)) }
        task.cancel()
        let result = try await task.value
        XCTAssertTrue(result.wasCancelled)
    }

    func testTypedRegexKindSizeAndStreamingBatches() async throws {
        let fixture = try SandboxFixture(testCase: self)
        _ = try fixture.allowedFile("typed/one.log", contents: "12345")
        _ = try fixture.allowedFile("typed/two.txt", contents: "12345")
        let query = DescendantSearchQuery(nameMatcher: .regularExpression(#"^one\.[a-z]+$"#), fileKinds: [.file], size: .init(minimumBytes: 5, maximumBytes: 5), scopes: [.folder(fixture.allowedDirectory, includeDescendants: true)])
        let batches = BatchRecorder()
        let result = try await DescendantSearchService(accessPolicy: fixture.policy).search(query: query, limits: .init(maximumItems: 10, maximumDepth: 10, timeout: 5, batchSize: 1)) { await batches.append($0) }
        XCTAssertEqual(result.items.map(\.name), ["one.log"])
        let batchCount = await batches.count
        XCTAssertEqual(batchCount, 1)
    }

    func testMalformedRegularExpressionIsRejected() async throws {
        let fixture = try SandboxFixture(testCase: self)
        let query = DescendantSearchQuery(nameMatcher: .regularExpression("["), scopes: [.folder(fixture.allowedDirectory, includeDescendants: true)])
        await XCTAssertThrowsErrorAsync(try await DescendantSearchService(accessPolicy: fixture.policy).search(query: query))
    }
}

private actor BatchRecorder { private var batches = [[DescendantSearchItem]](); func append(_ batch: [DescendantSearchItem]) { batches.append(batch) }; var count: Int { batches.count } }

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { }
}

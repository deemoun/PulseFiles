import XCTest
@testable import PulseFilesModels
@testable import PulseFilesUtilities

final class QuickSearchTests: XCTestCase {
    func testContainsReturnsOriginalStringRange() {
        let value = "Quarterly Report.txt"
        let match = QuickSearchMatcher.match("report", in: value, mode: .contains)
        XCTAssertEqual(match?.ranges.map { String(value[$0]) }, ["Report"])
    }

    func testPrefixAndSuffixRespectTheirEdges() {
        XCTAssertNotNil(QuickSearchMatcher.match("Read", in: "README.md", mode: .prefix))
        XCTAssertNil(QuickSearchMatcher.match("README", in: "MyREADME.md", mode: .prefix))
        XCTAssertNotNil(QuickSearchMatcher.match(".md", in: "README.md", mode: .suffix))
        XCTAssertNil(QuickSearchMatcher.match("READ", in: "README.md", mode: .suffix))
    }

    func testPrefixOrSuffixAcceptsEitherEdgeButNotMiddle() {
        XCTAssertNotNil(QuickSearchMatcher.match("photo", in: "Photos-2026", mode: .prefixOrSuffix))
        XCTAssertNotNil(QuickSearchMatcher.match("2026", in: "Photos-2026", mode: .prefixOrSuffix))
        XCTAssertNil(QuickSearchMatcher.match("tos", in: "Photos-2026", mode: .prefixOrSuffix))
    }

    func testFuzzyIsDeterministicAndReturnsCoalescedHighlightRanges() {
        let value = "Documentation.swift"
        let match = QuickSearchMatcher.match("dcs", in: value, mode: .fuzzy)
        XCTAssertEqual(match?.ranges.map { String(value[$0]) }, ["D", "c", "s"])
    }

    func testUnicodeMatchingIsCaseDiacriticAndCompositionStable() {
        let composed = "Café.txt"
        let decomposed = "Cafe\u{301}.txt"
        XCTAssertEqual(
            QuickSearchMatcher.match("CAFÉ", in: composed, mode: .prefix)?.ranges.map { String(composed[$0]) },
            ["Café"]
        )
        XCTAssertEqual(
            QuickSearchMatcher.match("cafe", in: decomposed, mode: .prefix)?.ranges.map { String(decomposed[$0]).precomposedStringWithCanonicalMapping },
            ["Café"]
        )
    }

    func testModesAndPresentationsRoundTripThroughCodable() throws {
        for value in QuickSearchMatchMode.allCases {
            XCTAssertEqual(try JSONDecoder().decode(QuickSearchMatchMode.self, from: JSONEncoder().encode(value)), value)
        }
        for value in QuickSearchPresentation.allCases {
            XCTAssertEqual(try JSONDecoder().decode(QuickSearchPresentation.self, from: JSONEncoder().encode(value)), value)
        }
    }
}

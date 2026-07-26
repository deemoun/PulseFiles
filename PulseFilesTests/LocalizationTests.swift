import Foundation
import XCTest
@testable import PulseFiles

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        LocalizationConfiguration.configure(language: .english)
        super.tearDown()
    }

    func testEnglishAndRussianResourceLookup() {
        LocalizationConfiguration.configure(language: .english)
        XCTAssertEqual("Settings".localized, "Settings")

        LocalizationConfiguration.configure(language: .russian)
        XCTAssertEqual("Settings".localized, "Настройки")
        XCTAssertEqual("This folder is empty".localized, "Эта папка пуста")
    }

    func testFormattedLocalizationUsesSelectedLanguage() {
        LocalizationConfiguration.configure(language: .russian)
        XCTAssertEqual("Version %@".localized(with: "2.0"), "Версия 2.0")
        XCTAssertEqual("%d Items".localized(with: 12), "Объектов: 12")
    }

    func testMissingKeyFallsBackToKey() {
        LocalizationConfiguration.configure(language: .russian)
        XCTAssertEqual("A deliberately missing localization key".localized, "A deliberately missing localization key")
    }

    func testEnglishAndRussianCatalogsHaveIdenticalKeysAndPlaceholders() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PulseFiles/Resources", isDirectory: true)
        let english = try catalog(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let russian = try catalog(at: resources.appendingPathComponent("ru.lproj/Localizable.strings"))

        XCTAssertEqual(Set(english.keys), Set(russian.keys))
        for key in english.keys {
            XCTAssertEqual(placeholders(in: english[key] ?? ""), placeholders(in: russian[key] ?? ""), "Placeholder mismatch for \(key)")
        }
    }

    private func catalog(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func placeholders(in string: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@d]"#)
        let range = NSRange(string.startIndex..., in: string)
        return expression.matches(in: string, range: range).compactMap { Range($0.range, in: string).map { String(string[$0]) } }
    }
}

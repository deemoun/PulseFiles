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
        let resources = localizationResources
        let english = try catalog(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let russian = try catalog(at: resources.appendingPathComponent("ru.lproj/Localizable.strings"))

        XCTAssertEqual(Set(english.keys), Set(russian.keys))
        for key in english.keys {
            XCTAssertEqual(placeholders(in: english[key] ?? ""), placeholders(in: russian[key] ?? ""), "Placeholder mismatch for \(key)")
        }
    }

    func testProductionCatalogsContainNoDesignatedTranslationPlaceholders() throws {
        let catalogURLs = [
            localizationResources.appendingPathComponent("en.lproj/Localizable.strings"),
            localizationResources.appendingPathComponent("ru.lproj/Localizable.strings")
        ]
        let placeholderPatterns = [
            #"(?i)^\s*Русский:\s*"#,
            #"(?i)^\s*(?:TODO|TBD)(?:\b|:)"#,
            #"(?i)<\s*(?:translate|translation|placeholder)\s*>"#
        ].map { try! NSRegularExpression(pattern: $0) }

        for url in catalogURLs {
            for (key, value) in try catalog(at: url) {
                let range = NSRange(value.startIndex..., in: value)
                for pattern in placeholderPatterns {
                    XCTAssertNil(
                        pattern.firstMatch(in: value, range: range),
                        "Production localization for \(key) in \(url.lastPathComponent) contains a placeholder: \(value)"
                    )
                }
            }
        }
    }

    func testHighRiskEnglishAndRussianMessagesAreExplicitAndReviewed() throws {
        let english = try catalog(at: localizationResources.appendingPathComponent("en.lproj/Localizable.strings"))
        let russian = try catalog(at: localizationResources.appendingPathComponent("ru.lproj/Localizable.strings"))
        let reviewedMessages: [String: (english: String, russian: String)] = [
            "Permanently Delete": ("Permanently Delete", "Удалить безвозвратно"),
            "Could not safely replace the existing item.": (
                "Could not safely replace the existing item.",
                "Не удалось безопасно заменить существующий объект."
            ),
            "The original item was kept at %@. %@ was not overwritten.": (
                "The original item was kept at %@. %@ was not overwritten.",
                "Исходный объект сохранён в %@. Объект %@ не был перезаписан."
            ),
            "The last operation cannot be safely undone.": (
                "The last operation cannot be safely undone.",
                "Последнюю операцию невозможно безопасно отменить."
            ),
            "Beta Terminal is disabled and hidden. Enable it only if you accept that shell commands can modify or delete files.": (
                "Beta Terminal is disabled and hidden. Enable it only if you accept that shell commands can modify or delete files.",
                "Бета-терминал выключен и скрыт. Включайте его, только если принимаете риск изменения или удаления файлов командами оболочки."
            )
        ]

        for (key, expected) in reviewedMessages {
            XCTAssertEqual(english[key], expected.english, "Unexpected English safety wording for \(key)")
            XCTAssertEqual(russian[key], expected.russian, "Unexpected Russian safety wording for \(key)")
        }
    }

    private var localizationResources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PulseFiles/Resources", isDirectory: true)
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

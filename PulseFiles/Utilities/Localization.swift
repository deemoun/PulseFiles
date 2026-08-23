import Foundation

package enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case russian = "ru"

    package var localizedDisplayName: String {
        switch self {
        case .english: return "English".localized
        case .russian: return "Russian".localized
        }
    }

    package var locale: Locale {
        Locale(identifier: rawValue == "ru" ? "ru_RU" : "en_US")
    }
}

/// The single synchronization point for application-controlled localization.
/// Bundle selection is immutable between explicit configuration calls, and all
/// reads are protected so background-created status strings are safe.
package enum LocalizationConfiguration {
    private static let lock = NSLock()
    private static var _language: AppLanguage = .english

    package static var language: AppLanguage {
        lock.withLock { _language }
    }

    package static func configure(language: AppLanguage) {
        lock.withLock { _language = language }
    }

    package static func localizedString(forKey key: String) -> String {
        let selectedLanguage = language
        let resources = Bundle.pulseFilesLocalization
        guard let path = resources.path(forResource: selectedLanguage.rawValue, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else {
            return resources.localizedString(forKey: key, value: key, table: nil)
        }
        return languageBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

package extension String {
    var localized: String {
        LocalizationConfiguration.localizedString(forKey: self)
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, locale: LocalizationConfiguration.language.locale, arguments: arguments)
    }
}

private extension Bundle {
    static var pulseFilesLocalization: Bundle {
        pulseFilesResourceBundle ?? .main
    }

    static var pulseFilesResourceBundle: Bundle? {
        let bundleName = "PulseFiles_PulseFiles"
        let candidateURLs = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: PulseFilesBundleFinder.self).resourceURL,
            Bundle(for: PulseFilesBundleFinder.self).bundleURL
        ]

        for candidateURL in candidateURLs.compactMap({ $0 }) {
            for bundleExtension in ["bundle", "resources"] {
                let bundleURL = candidateURL.appendingPathComponent(bundleName + "." + bundleExtension)
                if let bundle = Bundle(url: bundleURL) { return bundle }
            }
        }
        return nil
    }
}

private final class PulseFilesBundleFinder {}

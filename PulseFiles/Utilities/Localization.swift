import Foundation

extension String {
    var localized: String {
        NSLocalizedString(self, bundle: .pulseFilesLocalization, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, locale: .current, arguments: arguments)
    }
}

private extension Bundle {
    static var pulseFilesLocalization: Bundle {
        if let bundle = pulseFilesResourceBundle {
            return bundle
        }

        return .main
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
                if let bundle = Bundle(url: bundleURL) {
                    return bundle
                }
            }
        }

        return nil
    }
}

private final class PulseFilesBundleFinder {}

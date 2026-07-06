import Foundation

extension String {
    var localized: String {
        NSLocalizedString(self, bundle: .module, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, locale: .current, arguments: arguments)
    }
}

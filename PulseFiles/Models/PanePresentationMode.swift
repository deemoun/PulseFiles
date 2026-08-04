import Foundation
import PulseFilesUtilities

package enum PanePresentationMode: String, CaseIterable, Codable {
    case list
    case brief
    case gallery

    package var localizedTitle: String {
        switch self {
        case .list: return "List".localized
        case .brief: return "Brief".localized
        case .gallery: return "Gallery".localized
        }
    }
}

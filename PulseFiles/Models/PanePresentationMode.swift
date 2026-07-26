import Foundation

enum PanePresentationMode: String, CaseIterable, Codable {
    case list
    case brief
    case gallery

    var localizedTitle: String {
        switch self {
        case .list: return "List".localized
        case .brief: return "Brief".localized
        case .gallery: return "Gallery".localized
        }
    }
}

import Foundation

final class RecentLocationService {
    private let defaults: UserDefaults
    private let key = "recentLocations"
    private(set) var locations: [URL] = []
    var onChange: (([URL]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        locations = (defaults.array(forKey: key) ?? [])
            .compactMap { $0 as? String }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func record(_ url: URL) {
        locations.removeAll { $0 == url }
        locations.insert(url, at: 0)
        locations = Array(locations.prefix(12))
        defaults.set(locations.map(\.path), forKey: key)
        onChange?(locations)
    }
}

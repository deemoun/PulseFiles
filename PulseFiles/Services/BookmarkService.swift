import Foundation

final class BookmarkService {
    private let defaults: UserDefaults
    private let key = "bookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Bookmark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    func save(_ bookmarks: [Bookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: key)
        }
    }
}

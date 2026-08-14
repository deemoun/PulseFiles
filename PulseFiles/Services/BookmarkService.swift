import PulseFilesUtilities
import PulseFilesModels
import Foundation

package final class BookmarkService {
    private let defaults: UserDefaults
    private let key = "bookmarks"

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func load() -> [Bookmark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    package func save(_ bookmarks: [Bookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: key)
        }
    }

    @discardableResult func add(url: URL, title: String? = nil) -> [Bookmark] {
        var bookmarks = load()
        guard !bookmarks.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return bookmarks }
        bookmarks.append(Bookmark(title: title ?? url.lastPathComponent, url: url))
        save(bookmarks)
        return bookmarks
    }

    @discardableResult func remove(id: UUID) -> [Bookmark] {
        var bookmarks = load(); bookmarks.removeAll { $0.id == id }; save(bookmarks); return bookmarks
    }

    @discardableResult func rename(id: UUID, title: String) -> [Bookmark] {
        var bookmarks = load()
        if let index = bookmarks.firstIndex(where: { $0.id == id }) { bookmarks[index].title = title }
        save(bookmarks); return bookmarks
    }

    @discardableResult func move(id: UUID, to destination: Int) -> [Bookmark] {
        var bookmarks = load()
        guard let source = bookmarks.firstIndex(where: { $0.id == id }) else { return bookmarks }
        let bookmark = bookmarks.remove(at: source)
        bookmarks.insert(bookmark, at: min(max(0, destination), bookmarks.count))
        save(bookmarks); return bookmarks
    }
}

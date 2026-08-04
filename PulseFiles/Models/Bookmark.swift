import Foundation
import PulseFilesUtilities

package struct Bookmark: Codable, Identifiable, Equatable {
    package var id: UUID
    package var title: String
    package var url: URL

    package init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

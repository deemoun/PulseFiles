import Foundation
import PulseFilesUtilities

package struct NavigationHistory: Codable, Equatable {
    package private(set) var backStack: [URL] = []
    package private(set) var forwardStack: [URL] = []
    package private(set) var current: URL

    package init(initialURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        current = initialURL
    }

    package var canGoBack: Bool { !backStack.isEmpty }
    package var canGoForward: Bool { !forwardStack.isEmpty }

    package mutating func visit(_ url: URL) {
        guard url != current else { return }
        backStack.append(current)
        current = url
        forwardStack.removeAll()
    }

    package mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    package mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }
}

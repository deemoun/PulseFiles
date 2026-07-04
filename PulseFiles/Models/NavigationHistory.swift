import Foundation

struct NavigationHistory {
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    private(set) var current: URL

    init(initialURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        current = initialURL
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    mutating func visit(_ url: URL) {
        guard url != current else { return }
        backStack.append(current)
        current = url
        forwardStack.removeAll()
    }

    mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }
}

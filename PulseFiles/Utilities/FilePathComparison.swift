import Foundation

enum FilePathComparison {
    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    static func isSameOrDescendant(_ candidate: URL, ofDirectory directory: URL) -> Bool {
        let candidatePath = normalizedPath(candidate)
        let directoryPath = normalizedPath(directory)
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }
}

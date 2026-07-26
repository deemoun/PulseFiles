import Foundation

struct FileNameValidator {
    enum ValidationError: LocalizedError, Equatable {
        case empty
        case containsSlash
        case reservedRelativePath
        case containsNullCharacter
        case reservedName(String)
        case duplicateName(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Names cannot be empty or contain only whitespace.".localized
            case .containsSlash:
                return "Names cannot contain slashes (/).".localized
            case .reservedRelativePath:
                return "The names . and .. are reserved for folder navigation.".localized
            case .containsNullCharacter:
                return "Names cannot contain null characters.".localized
            case .reservedName(let name):
                return "%@ is reserved by macOS and cannot be used as a file name.".localized(with: name)
            case .duplicateName(let existingName):
                return "An item named %@ already exists in this folder.".localized(with: existingName)
            }
        }
    }

    static let reservedNames: Set<String> = [
        ".DS_Store",
        ".localized",
        "Icon\r"
    ]

    static func validate(
        _ rawName: String,
        in directory: URL,
        replacing existingItemURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        let name = try validateSyntax(rawName)

        let shouldCaseFoldDuplicates = try shouldCheckCaseInsensitiveCollisions(in: directory, fileManager: fileManager)
        if let duplicateName = try duplicateName(for: name, in: directory, replacing: existingItemURL, caseFold: shouldCaseFoldDuplicates, fileManager: fileManager) {
            throw ValidationError.duplicateName(duplicateName)
        }

        return name
    }

    /// Validates a proposed name without consulting directory contents. This
    /// is used by batch-rename preflight, where existing sources may legally be
    /// one another's destinations and are moved through private temporary names.
    static func validateSyntax(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.empty }
        guard !name.contains("/") else { throw ValidationError.containsSlash }
        guard name != ".", name != ".." else { throw ValidationError.reservedRelativePath }
        guard !name.contains("\0") else { throw ValidationError.containsNullCharacter }
        if reservedNames.contains(name) { throw ValidationError.reservedName(name) }
        return name
    }

    private static func shouldCheckCaseInsensitiveCollisions(in directory: URL, fileManager: FileManager) throws -> Bool {
        let values = try directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values.volumeSupportsCaseSensitiveNames == false
    }

    private static func duplicateName(for name: String, in directory: URL, replacing existingItemURL: URL?, caseFold: Bool, fileManager: FileManager) throws -> String? {
        let candidateKey = comparisonKey(for: name)
        let existingCanonicalURL = existingItemURL?.standardizedFileURL.resolvingSymlinksInPath()
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])

        for itemURL in contents {
            if let existingCanonicalURL,
               itemURL.standardizedFileURL.resolvingSymlinksInPath() == existingCanonicalURL {
                continue
            }

            let existingName = itemURL.lastPathComponent
            if existingName == name || (caseFold && comparisonKey(for: existingName) == candidateKey) {
                return existingName
            }
        }

        return nil
    }

    private static func comparisonKey(for name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

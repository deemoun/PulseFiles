import AppKit

/// Defines the safe table-refresh behavior while AppKit owns an inline editor.
enum InlineRenameReloadPolicy {
    enum Decision: Equatable {
        case reloadNow
        case deferReload
        case cancelRenameAndReload
    }

    static func decision(isEditing: Bool, itemExists: Bool) -> Decision {
        guard isEditing else { return .reloadNow }
        return itemExists ? .deferReload : .cancelRenameAndReload
    }
}

/// Tracks one edit independently from the table's lifecycle callbacks.
struct InlineRenameCommitSession {
    enum Result: Equatable { case rename(URL, String), noChange, cancelled, ignored }
    private(set) var itemURL: URL?
    private(set) var normalizedItemPath: String?
    private(set) var generation: UInt = 0
    var isEditing: Bool { itemURL != nil }

    mutating func begin(for itemURL: URL) {
        generation &+= 1
        self.itemURL = itemURL
        normalizedItemPath = normalizedPath(for: itemURL)
    }
    func generation(for itemURL: URL) -> UInt? { matches(itemURL: itemURL, generation: generation) ? generation : nil }
    func matches(itemURL: URL, generation: UInt) -> Bool {
        normalizedItemPath != nil && self.generation == generation && normalizedItemPath == normalizedPath(for: itemURL)
    }
    mutating func commit(itemURL: URL, generation: UInt, proposedName: String, originalName: String?, isCancelled: Bool) -> Result {
        guard matches(itemURL: itemURL, generation: generation) else { return .ignored }
        defer { cancel() }
        guard !isCancelled else { return .cancelled }
        guard let originalName else { return .cancelled }
        guard proposedName != originalName else { return .noChange }
        return .rename(itemURL, proposedName)
    }
    mutating func cancel() { itemURL = nil; normalizedItemPath = nil }
    private func normalizedPath(for url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
}

/// Owns AppKit editor callback decoding while the pane controller retains item identity and rename intent.
final class InlineRenameCoordinator: NSObject, NSTextFieldDelegate {
    var onCommit: ((URL?, UInt?, String, Bool) -> Void)?

    func configure(_ field: InlineRenameTextField, itemURL: URL, generation: UInt?) {
        field.itemURL = itemURL
        field.sessionGeneration = generation
        field.delegate = self
        field.target = self
        field.action = #selector(commitFromAction(_:))
    }

    @objc private func commitFromAction(_ sender: InlineRenameTextField) {
        onCommit?(sender.itemURL, sender.sessionGeneration, sender.stringValue, false)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? InlineRenameTextField else { return }
        let movement = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        onCommit?(field.itemURL, field.sessionGeneration, field.stringValue, movement == NSCancelTextMovement)
    }
}

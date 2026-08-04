import AppKit

/// Name-column editor carrying stable item and edit-session identities across table reload callbacks.
final class InlineRenameTextField: NSTextField {
    var itemURL: URL?
    var sessionGeneration: UInt?
}

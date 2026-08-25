import AppKit

/// Name-column editor carrying stable item and edit-session identities across table reload callbacks.
package final class InlineRenameTextField: NSTextField {
    package var itemURL: URL?
    package var sessionGeneration: UInt?
}

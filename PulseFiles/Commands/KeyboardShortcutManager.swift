import AppKit

final class KeyboardShortcutManager {
    static func isCommandPeriodToggleHidden(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers == "."
    }
}

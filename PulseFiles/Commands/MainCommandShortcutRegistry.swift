import AppKit

/// The authoritative keyboard and menu presentation metadata for application commands.
struct MainCommandShortcut: Equatable {
    enum Scope: Equatable {
        /// The shortcut may be used while a text field is the first responder.
        case textInputSafe
        /// The shortcut is reserved for file-manager interaction, not text editing.
        case outsideTextInput
    }

    let command: MainCommand
    let keyEquivalent: String
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let displayLabel: String
    let scope: Scope
}

enum MainCommandShortcutRegistry {
    static let shortcuts: [MainCommandShortcut] = [
        shortcut(.open, "", 36, [], "F3 / F4", .outsideTextInput),
        shortcut(.openWith, "", 65_535, [], ""),
        shortcut(.quickLook, "", 49, [], "Space", .outsideTextInput),
        shortcut(.newFile, "n", 45, [.command, .shift], "Shift F7", .outsideTextInput),
        shortcut(.newFolder, "n", 45, [.command], "F7", .outsideTextInput),
        shortcut(.rename, "", 120, [], "F2", .outsideTextInput),
        shortcut(.duplicate, "d", 2, [.command], "⌘D", .outsideTextInput),
        shortcut(.getInfo, "i", 34, [.command], "⌘I", .outsideTextInput),
        shortcut(.selectAll, "a", 0, [.command], "⌘A", .outsideTextInput),
        shortcut(.invertSelection, "i", 34, [.command, .shift], "⌘⇧I", .outsideTextInput),
        shortcut(.undo, "z", 6, [.command], "⌘Z", .outsideTextInput),
        shortcut(.copy, "", 96, [], "F5", .outsideTextInput),
        shortcut(.move, "m", 46, [.command], "F6", .outsideTextInput),
        shortcut(.copyToClipboard, "c", 8, [.command], "⌘C", .outsideTextInput),
        shortcut(.cutToClipboard, "x", 7, [.command], "⌘X", .outsideTextInput),
        shortcut(.pasteFromClipboard, "v", 9, [.command], "⌘V", .outsideTextInput),
        shortcut(.trash, "\u{8}", 51, [.command], "F8", .outsideTextInput),
        shortcut(.refresh, "r", 15, [.command], "⌘R", .outsideTextInput),
        shortcut(.reveal, "r", 15, [.command, .shift], "⌘⇧R", .outsideTextInput),
        shortcut(.toggleHiddenFiles, ".", 47, [.command, .shift], "⌘⇧.", .outsideTextInput),
        shortcut(.sortByName, "", 65_535, [], ""), shortcut(.sortByKind, "", 65_535, [], ""),
        shortcut(.sortBySize, "", 65_535, [], ""), shortcut(.sortByModified, "", 65_535, [], ""),
        shortcut(.sortAscending, "", 65_535, [], ""), shortcut(.sortDescending, "", 65_535, [], ""),
        shortcut(.toggleTerminal, "`", 50, [.command], "⌘`", .textInputSafe),
        shortcut(.toggleSidebar, "s", 1, [.command, .option], "⌥⌘S", .outsideTextInput),
        shortcut(.togglePaneLayout, "t", 17, [.command], "⌘T", .outsideTextInput),
        shortcut(.back, "[", 33, [.command], "⌘[", .outsideTextInput),
        shortcut(.forward, "]", 30, [.command], "⌘]", .outsideTextInput),
        shortcut(.parent, "\u{F700}", 126, [.command], "⌘↑", .outsideTextInput),
        shortcut(.goToFolder, "g", 5, [.command, .shift], "⌘⇧G", .outsideTextInput),
        shortcut(.searchDescendants, "f", 3, [.command, .shift], "⌘⇧F", .outsideTextInput),
        shortcut(.home, "h", 4, [.command, .shift], "⌘⇧H", .outsideTextInput),
        shortcut(.downloads, "l", 37, [.command, .option], "⌥⌘L", .outsideTextInput),
        shortcut(.applications, "a", 0, [.command, .shift], "⌘⇧A", .outsideTextInput),
        shortcut(.scratchDirectory, "g", 5, [.command, .control], "⌃⌘G", .outsideTextInput),
        shortcut(.switchPane, "\t", 48, [], "Tab", .outsideTextInput),
        shortcut(.cancelOperation, ".", 47, [.command], "⌘.", .textInputSafe),
        shortcut(.debugLogs, "", 65_535, [], ""), shortcut(.exportDiagnostics, "", 65_535, [], ""),
        shortcut(.open, "", 99, [], "F3", .outsideTextInput),
        shortcut(.open, "", 118, [], "F4", .outsideTextInput),
        shortcut(.newFile, "", 98, [.shift], "Shift F7", .outsideTextInput),
        shortcut(.newFolder, "", 98, [], "F7", .outsideTextInput),
        shortcut(.move, "", 97, [], "F6", .outsideTextInput),
        shortcut(.trash, "", 100, [], "F8", .outsideTextInput),
        shortcut(.trash, "", 51, [.shift], "Shift Delete", .outsideTextInput),
        shortcut(.parent, "", 51, [], "Delete", .outsideTextInput),
        shortcut(.scratchDirectory, "g", 5, [.command, .control, .option], "⌥⌃⌘G", .outsideTextInput)
    ]

    static func shortcut(for command: MainCommand) -> MainCommandShortcut {
        guard let shortcut = shortcuts.first(where: { $0.command == command }) else {
            preconditionFailure("Every MainCommand must have shortcut metadata.")
        }
        return shortcut
    }

    static func hasKeyboardShortcut(_ shortcut: MainCommandShortcut) -> Bool {
        shortcut.keyCode != 65_535
    }

    static func command(forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, isTextInputFocused: Bool) -> MainCommand? {
        let relevantFlags = modifierFlags.intersection([.command, .shift, .option, .control])
        return shortcuts.first(where: {
            $0.keyCode != 65_535 && $0.keyCode == keyCode
                && $0.modifierFlags == relevantFlags
                && (!isTextInputFocused || $0.scope == .textInputSafe)
        })?.command
    }

    /// AppKit's table view treats otherwise-unhandled Delete key combinations as
    /// text-editing actions. A file table is not editable through those actions,
    /// so keep unsupported Delete variants from reaching `NSTableView`.
    static func shouldConsumeUnmappedKey(keyCode: UInt16, isTextInputFocused: Bool) -> Bool {
        !isTextInputFocused && (keyCode == 51 || keyCode == 117)
    }

    private static func shortcut(_ command: MainCommand, _ keyEquivalent: String, _ keyCode: UInt16, _ modifierFlags: NSEvent.ModifierFlags, _ displayLabel: String, _ scope: MainCommandShortcut.Scope = .outsideTextInput) -> MainCommandShortcut {
        MainCommandShortcut(command: command, keyEquivalent: keyEquivalent, keyCode: keyCode, modifierFlags: modifierFlags, displayLabel: displayLabel, scope: scope)
    }
}

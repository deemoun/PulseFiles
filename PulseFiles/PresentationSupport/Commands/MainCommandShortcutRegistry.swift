// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesWorkflows

/// The authoritative keyboard and menu presentation metadata for one command.
package struct MainCommandShortcutDescriptor: Equatable {
    package struct MenuKeyEquivalent: Equatable {
        package let key: String
        package let modifierFlags: NSEvent.ModifierFlags
    }

    package struct PhysicalBinding: Equatable {
        package enum Scope: Equatable {
            /// The binding may be used while a text field is the first responder.
            case textInputSafe
            /// The binding is reserved for file-manager interaction, not text editing.
            case outsideTextInput
        }

        package let keyCode: UInt16
        package let modifierFlags: NSEvent.ModifierFlags
        package let scope: Scope
    }

    package let command: MainCommand
    package let menuKeyEquivalent: MenuKeyEquivalent?
    package let primaryLabel: String
    package let bindings: [PhysicalBinding]
}

package enum MainCommandShortcutRegistry {
    package typealias Descriptor = MainCommandShortcutDescriptor
    package typealias Binding = Descriptor.PhysicalBinding
    package typealias Scope = Binding.Scope

    package static let descriptors: [Descriptor] = [
        descriptor(.open, label: "Return / F4", bindings: [binding(36), binding(118)]),
        descriptor(.viewer, label: "F3", bindings: [binding(99)]),
        descriptor(.openWith),
        descriptor(.quickLook, label: "Space", bindings: [binding(49)]),
        descriptor(.newFile, menu: menu("n", [.command, .shift]), label: "Shift F7", bindings: [binding(45, [.command, .shift]), binding(98, [.shift])]),
        descriptor(.newFolder, menu: menu("n", [.command]), label: "F7", bindings: [binding(45, [.command]), binding(98)]),
        descriptor(.rename, label: "F2", bindings: [binding(120)]),
        descriptor(.batchRename), descriptor(.createArchive), descriptor(.extractArchive),
        descriptor(.duplicate, menu: menu("d", [.command]), label: "⌘D", bindings: [binding(2, [.command])]),
        descriptor(.getInfo, menu: menu("i", [.command]), label: "⌘I", bindings: [binding(34, [.command])]),
        descriptor(.selectAll, menu: menu("a", [.command]), label: "⌘A", bindings: [binding(0, [.command])]),
        descriptor(.deselectAll, menu: menu("a", [.command, .option]), label: "⌥⌘A", bindings: [binding(0, [.command, .option])]),
        descriptor(.selectByPattern, menu: menu("=", [.command]), label: "⌘=", bindings: [binding(24, [.command])]),
        descriptor(.deselectByPattern, menu: menu("-", [.command]), label: "⌘-", bindings: [binding(27, [.command])]),
        descriptor(.selectSameExtension, menu: menu("=", [.command, .option]), label: "⌥⌘=", bindings: [binding(24, [.command, .option])]),
        descriptor(.deselectSameExtension, menu: menu("-", [.command, .option]), label: "⌥⌘-", bindings: [binding(27, [.command, .option])]),
        descriptor(.invertSelection, menu: menu("i", [.command, .shift]), label: "⌘⇧I", bindings: [binding(34, [.command, .shift])]),
        descriptor(.undo, menu: menu("z", [.command]), label: "⌘Z", bindings: [binding(6, [.command])]),
        descriptor(.copy, label: "F5", bindings: [binding(96)]), descriptor(.move, label: "F6", bindings: [binding(97)]),
        descriptor(.copyToClipboard, menu: menu("c", [.command]), label: "⌘C", bindings: [binding(8, [.command])]),
        descriptor(.cutToClipboard, menu: menu("x", [.command]), label: "⌘X", bindings: [binding(7, [.command])]),
        descriptor(.pasteFromClipboard, menu: menu("v", [.command]), label: "⌘V", bindings: [binding(9, [.command])]),
        descriptor(.trash, menu: menu("\u{8}", [.command]), label: "F8", bindings: [binding(51, [.command]), binding(100), binding(51, [.shift])]),
        descriptor(.refresh, menu: menu("r", [.command]), label: "⌘R", bindings: [binding(15, [.command])]),
        descriptor(.reveal, menu: menu("r", [.command, .shift]), label: "⌘⇧R", bindings: [binding(15, [.command, .shift])]),
        descriptor(.toggleHiddenFiles, menu: menu(".", [.command, .shift]), label: "⌘⇧.", bindings: [binding(47, [.command, .shift])]),
        sortDescriptor(.sortByName, "1", 18), sortDescriptor(.sortByExtension, "2", 19),
        sortDescriptor(.sortByKind, "3", 20), sortDescriptor(.sortBySize, "4", 21),
        sortDescriptor(.sortByModified, "5", 23), sortDescriptor(.sortByCreated, "6", 22),
        sortDescriptor(.sortByAdded, "7", 26), descriptor(.sortByAccessed),
        descriptor(.sortAscending), descriptor(.sortDescending),
        descriptor(.toggleTerminal, menu: menu("`", [.command]), label: "⌘`", bindings: [binding(50, [.command], .textInputSafe)]),
        descriptor(.toggleSidebar, menu: menu("s", [.command, .option]), label: "⌥⌘S", bindings: [binding(1, [.command, .option])]),
        descriptor(.togglePaneLayout, menu: menu("\\", [.command, .option]), label: "⌥⌘\\", bindings: [binding(42, [.command, .option])]),
        descriptor(.newTab, menu: menu("t", [.command]), label: "⌘T", bindings: [binding(17, [.command])]),
        descriptor(.closeTab, menu: menu("w", [.command]), label: "⌘W", bindings: [binding(13, [.command])]),
        descriptor(.nextTab, menu: menu("\t", [.control]), label: "⌃Tab", bindings: [binding(48, [.control])]),
        descriptor(.previousTab, menu: menu("\t", [.control, .shift]), label: "⌃⇧Tab", bindings: [binding(48, [.control, .shift])]),
        descriptor(.back, menu: menu("[", [.command]), label: "⌘[", bindings: [binding(33, [.command])]),
        descriptor(.forward, menu: menu("]", [.command]), label: "⌘]", bindings: [binding(30, [.command])]),
        descriptor(.parent, menu: menu("\u{F700}", [.command]), label: "⌘↑", bindings: [binding(126, [.command]), binding(51)]),
        descriptor(.goToFolder, menu: menu("g", [.command, .shift]), label: "⌘⇧G", bindings: [binding(5, [.command, .shift])]),
        descriptor(.quickLocations, label: "F1", bindings: [binding(122)]),
        descriptor(.searchDescendants, menu: menu("f", [.command, .shift]), label: "⌘⇧F", bindings: [binding(3, [.command, .shift])]),
        descriptor(.home, menu: menu("h", [.command, .shift]), label: "⌘⇧H", bindings: [binding(4, [.command, .shift])]),
        descriptor(.downloads, menu: menu("l", [.command, .option]), label: "⌥⌘L", bindings: [binding(37, [.command, .option])]),
        descriptor(.applications, menu: menu("a", [.command, .shift]), label: "⌘⇧A", bindings: [binding(0, [.command, .shift])]),
        descriptor(.scratchDirectory, menu: menu("g", [.command, .control]), label: "⌃⌘G", bindings: [binding(5, [.command, .control]), binding(5, [.command, .control, .option])]),
        descriptor(.switchPane, menu: menu("\t", []), label: "Tab", bindings: [binding(48)]),
        descriptor(.swapPanes, menu: menu("u", [.command]), label: "⌘U", bindings: [binding(32, [.command])]),
        descriptor(.syncOppositePane, menu: menu("u", [.command, .option]), label: "⌥⌘U", bindings: [binding(32, [.command, .option])]),
        descriptor(.revealInOppositePane, menu: menu("\r", [.option]), label: "⌥Return", bindings: [binding(36, [.option])]),
        descriptor(.followSymbolicLink, menu: menu("\u{F703}", [.command]), label: "⌘→", bindings: [binding(124, [.command])]),
        descriptor(.cancelOperation, menu: menu(".", [.command]), label: "⌘.", bindings: [binding(47, [.command], .textInputSafe)]),
        descriptor(.debugLogs), descriptor(.exportDiagnostics)
    ]

    package static func descriptor(for command: MainCommand) -> Descriptor {
        guard let descriptor = descriptors.first(where: { $0.command == command }) else {
            preconditionFailure("Every MainCommand must have shortcut metadata.")
        }
        return descriptor
    }

    package static func command(forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, isTextInputFocused: Bool) -> MainCommand? {
        let relevantFlags = modifierFlags.intersection([.command, .shift, .option, .control])
        return descriptors.first(where: { descriptor in
            descriptor.bindings.contains {
                $0.keyCode == keyCode && $0.modifierFlags == relevantFlags
                    && (!isTextInputFocused || $0.scope == .textInputSafe)
            }
        })?.command
    }

    package static func shouldConsumeUnmappedKey(keyCode: UInt16, isTextInputFocused: Bool) -> Bool {
        !isTextInputFocused && (keyCode == 51 || keyCode == 117)
    }

    private static func descriptor(_ command: MainCommand, menu: Descriptor.MenuKeyEquivalent? = nil, label: String = "", bindings: [Binding] = []) -> Descriptor {
        Descriptor(command: command, menuKeyEquivalent: menu, primaryLabel: label, bindings: bindings)
    }

    private static func menu(_ key: String, _ flags: NSEvent.ModifierFlags) -> Descriptor.MenuKeyEquivalent {
        Descriptor.MenuKeyEquivalent(key: key, modifierFlags: flags)
    }

    private static func binding(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], _ scope: Scope = .outsideTextInput) -> Binding {
        Binding(keyCode: keyCode, modifierFlags: flags, scope: scope)
    }

    private static func sortDescriptor(_ command: MainCommand, _ key: String, _ keyCode: UInt16) -> Descriptor {
        descriptor(command, menu: menu(key, [.command, .control]), label: "⌃⌘\(key)", bindings: [binding(keyCode, [.command, .control])])
    }
}

extension CommandBarAction {
    package var shortcut: String {
        MainCommandShortcutRegistry.descriptor(for: MainCommand(commandBarAction: self)).primaryLabel
    }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PulseFilesWorkflows

extension MainCommandRouter {
    func commandForKeyDown(
        keyCode: UInt16,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false,
        isTextInputFocused: Bool = false
    ) -> MainCommand? {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return MainCommandShortcutRegistry.command(forKeyCode: keyCode, modifierFlags: flags, isTextInputFocused: isTextInputFocused)
    }

    func commandForKeyDown(_ event: NSEvent, isTextInputFocused: Bool) -> MainCommand? {
        MainCommandShortcutRegistry.command(forKeyCode: event.keyCode, modifierFlags: event.modifierFlags, isTextInputFocused: isTextInputFocused)
    }

    func shouldConsumeUnmappedKeyDown(keyCode: UInt16, isTextInputFocused: Bool = false) -> Bool {
        MainCommandShortcutRegistry.shouldConsumeUnmappedKey(keyCode: keyCode, isTextInputFocused: isTextInputFocused)
    }
}

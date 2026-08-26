// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

/// Per-window, non-persistent state. A new window/session intentionally does not
/// inherit manual terminal visibility changes from another settings instance.
package final class WindowSessionState {
    package var runtimeTerminalVisible: Bool?
}

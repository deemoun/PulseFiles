// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

// Split-view behavior is implemented by PaneArrangementCoordinator. Keeping only
// window and menu validation here makes these remaining controller roles explicit.
extension MainWindowViewController: NSWindowDelegate, NSMenuItemValidation {}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The terminal feature's narrow input boundary. Warning and visibility policy
/// remains in the composition layer; this module only needs shell configuration.
package protocol TerminalSessionProviding: AnyObject {
    var shellPath: String { get }
    var defaultEnvironment: [String: String] { get }
}

// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Converts command-routing rejections into user-facing presentation without coupling the router to AppKit alerts.
struct CommandPresentationCoordinator {
    struct Feedback: Equatable { let message: String; let detail: String }

    func feedback(for reason: MainCommandRoutingDisabledReason, parentRowFocused: Bool) -> Feedback {
        switch reason {
        case .fileOperationInProgress: return .init(message: "Operation in Progress", detail: "Wait for the current file operation to finish before starting another file-changing action.")
        case .noOppositePane: return .init(message: "Opposite Pane Unavailable", detail: "Use dual-pane mode before using this command.")
        case .noSelection: return parentRowFocused ? parentRowFeedback : .init(message: "Nothing Selected", detail: "Select one or more items before using this command.")
        case .noFocusedItem, .noRealFocusedItem: return parentRowFocused ? parentRowFeedback : .init(message: "Nothing Focused", detail: "Focus an item before using this command.")
        case .sandboxRejectedSelection: return .init(message: "Access Denied", detail: "The selected item is outside the locations PulseFiles is allowed to access.")
        case .noActiveFileOperation: return .init(message: "No Operation in Progress", detail: "There is no active file operation to cancel.")
        case .noUndoRecovery: return .init(message: "Undo Unavailable", detail: "The last operation cannot be safely undone.")
        case .focusedItemIsNotSymbolicLink: return .init(message: "Not a Symbolic Link", detail: "Focus a symbolic link before using this command.")
        case .lastTab: return .init(message: "Last Tab", detail: "Each pane must keep at least one tab open.")
        }
    }

    private var parentRowFeedback: Feedback {
        .init(message: "Parent Folder Focused", detail: "This command requires an item inside the current folder. Press Right Arrow or Return to open the parent folder.")
    }
}

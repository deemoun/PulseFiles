import Foundation

struct PaneKeyboardModifiers: OptionSet, Equatable {
    let rawValue: UInt

    static let command = PaneKeyboardModifiers(rawValue: 1 << 0)
    static let shift = PaneKeyboardModifiers(rawValue: 1 << 1)
    static let option = PaneKeyboardModifiers(rawValue: 1 << 2)
    static let control = PaneKeyboardModifiers(rawValue: 1 << 3)
}

enum PaneKeyboardNavigationAction: Equatable {
    case moveFocus(delta: Int)
    case openFocusedItem
    case navigateToParent
    case unhandled
}

/// Converts hardware key input into pane navigation without depending on an
/// AppKit responder chain. Modified arrows are deliberately left to AppKit's
/// standard table-selection handling.
final class PaneKeyboardNavigationController {
    func action(keyCode: UInt16, modifiers: PaneKeyboardModifiers) -> PaneKeyboardNavigationAction {
        guard modifiers.isEmpty else { return .unhandled }

        switch keyCode {
        case 123: return .navigateToParent
        case 124: return .openFocusedItem
        case 125: return .moveFocus(delta: 1)
        case 126: return .moveFocus(delta: -1)
        default: return .unhandled
        }
    }
}

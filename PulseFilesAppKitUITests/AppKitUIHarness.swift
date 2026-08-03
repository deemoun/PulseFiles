import AppKit
import XCTest
@testable import PulseFiles

/// A deterministic replacement for an Xcode UI-test bundle.
///
/// Swift Package Manager does not support `XCUIApplication` targets. This
/// harness builds the same `MainWindowController` used by the app, puts its
/// window on screen, and locates controls exactly as assistive technologies
/// do: by `AccessibilityIdentifiers`. It deliberately never relies on view
/// hierarchy indexes or localized labels.
@MainActor
final class AppKitUIHarness {
    let windowController: MainWindowController

    init() {
        // NSWindow construction requires the shared application to exist.
        _ = NSApplication.shared
        windowController = MainWindowController()
    }

    var window: NSWindow {
        guard let window = windowController.window else {
            fatalError("MainWindowController did not create a window")
        }
        return window
    }

    func launch() {
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    func element(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> NSView {
        let toolbarElement = window.toolbar?.items.lazy.compactMap { item in
            findView(in: item.view, identifier: identifier)
        }.first
        guard let element = findView(in: window.contentView, identifier: identifier) ?? toolbarElement else {
            XCTFail("Missing accessibility element \(identifier)", file: file, line: line)
            fatalError("Missing accessibility element \(identifier)")
        }
        return element
    }

    func activate(_ selector: Selector) {
        guard let controller = window.contentViewController else { return }
        _ = controller.perform(selector, with: nil)
        window.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    /// Sends a hardware-style key event through NSApplication so local event
    /// monitors, command routing, the window, and the current first responder
    /// participate exactly as they do for a real key press.
    func postKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) throws {
        let characters: [UInt16: String] = [
            123: "\u{F702}", 124: "\u{F703}",
            125: "\u{F701}", 126: "\u{F700}"
        ]
        let character = characters[keyCode] ?? ""
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: isRepeat,
            keyCode: keyCode
        ))
        NSApplication.shared.postEvent(event, atStart: false)
        let posted = try XCTUnwrap(NSApplication.shared.nextEvent(
            matching: .keyDown,
            until: Date(timeIntervalSinceNow: 1),
            inMode: .default,
            dequeue: true
        ))
        NSApplication.shared.sendEvent(posted)
    }

    func close() {
        window.orderOut(nil)
        windowController.close()
    }

    private func findView(in view: NSView?, identifier: String) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == identifier { return view }
        return view.subviews.lazy.compactMap { findView(in: $0, identifier: identifier) }.first
    }
}

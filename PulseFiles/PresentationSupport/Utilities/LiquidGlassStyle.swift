import AppKit

/// Immutable presentation values for the optional liquid-glass appearance.
/// Persistence deliberately lives outside this type; composition roots create a
/// value from `SettingsService` and inject it into the views they own.
struct LiquidGlassStyle: Equatable {
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 8

    let isEnabled: Bool

    init(liquidGlassEnabled: Bool) {
        isEnabled = liquidGlassEnabled
    }

    var windowBackground: NSColor {
        isEnabled ? NSColor(calibratedRed: 0.045, green: 0.061, blue: 0.078, alpha: 1) : .windowBackgroundColor
    }
    var panelFill: NSColor {
        isEnabled ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: 0.045) : .controlBackgroundColor
    }
    var panelStroke: NSColor {
        isEnabled ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: 0.105) : .separatorColor
    }
    var subtleStroke: NSColor {
        isEnabled ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: 0.07) : .separatorColor
    }
    var activeStroke: NSColor { NSColor.systemBlue.withAlphaComponent(isEnabled ? 0.58 : 0.7) }
    var activeFill: NSColor { NSColor.systemBlue.withAlphaComponent(isEnabled ? 0.125 : 0.08) }
    var label: NSColor { isEnabled ? NSColor(calibratedWhite: 0.9, alpha: 1) : .labelColor }
    var secondaryLabel: NSColor { isEnabled ? NSColor(calibratedWhite: 0.68, alpha: 1) : .secondaryLabelColor }

    func applyPanelChrome(to view: NSView, radius: CGFloat = cornerRadius) {
        view.wantsLayer = true
        view.layer?.cornerRadius = isEnabled ? radius : Self.compactCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = panelFill.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = panelStroke.cgColor
    }

    func applyButtonChrome(to button: NSButton) {
        button.bezelStyle = isEnabled ? .regularSquare : .rounded
        button.isBordered = !isEnabled
        button.wantsLayer = true
        button.layer?.cornerRadius = Self.compactCornerRadius
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = isEnabled ? NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.0, alpha: 0.055).cgColor : NSColor.clear.cgColor
        button.layer?.borderWidth = isEnabled ? 1 : 0
        button.layer?.borderColor = isEnabled ? subtleStroke.cgColor : NSColor.clear.cgColor
        button.contentTintColor = isEnabled ? label : nil
    }

    func applyDestructiveButtonChrome(to button: NSButton) {
        applyButtonChrome(to: button)
        button.contentTintColor = .systemRed
        guard isEnabled else { return }
        button.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.095).cgColor
        button.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.28).cgColor
    }
}

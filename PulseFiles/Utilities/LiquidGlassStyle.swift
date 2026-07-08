import AppKit

enum LiquidGlassStyle {
    static let preferenceKey = "liquidGlassEnabled"
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 8
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? false }
    static var windowBackground: NSColor {
        isEnabled ? NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.095, alpha: 1) : .windowBackgroundColor
    }
    static var panelFill: NSColor {
        isEnabled ? NSColor(calibratedWhite: 1.0, alpha: 0.045) : .controlBackgroundColor
    }
    static var panelStroke: NSColor {
        isEnabled ? NSColor(calibratedWhite: 1.0, alpha: 0.12) : .separatorColor
    }
    static var subtleStroke: NSColor {
        isEnabled ? NSColor(calibratedWhite: 1.0, alpha: 0.08) : .separatorColor
    }
    static let activeStroke = NSColor.systemBlue.withAlphaComponent(0.7)
    static var activeFill: NSColor { NSColor.systemBlue.withAlphaComponent(isEnabled ? 0.16 : 0.08) }
    static var label: NSColor { isEnabled ? NSColor(calibratedWhite: 0.9, alpha: 1) : .labelColor }
    static var secondaryLabel: NSColor { isEnabled ? NSColor(calibratedWhite: 0.68, alpha: 1) : .secondaryLabelColor }

    static func applyPanelChrome(to view: NSView, radius: CGFloat = cornerRadius) {
        view.wantsLayer = true
        view.layer?.cornerRadius = isEnabled ? radius : compactCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = panelFill.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = panelStroke.cgColor
    }

    static func applyButtonChrome(to button: NSButton) {
        button.bezelStyle = isEnabled ? .regularSquare : .rounded
        button.isBordered = !isEnabled
        button.wantsLayer = true
        button.layer?.cornerRadius = compactCornerRadius
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = isEnabled ? NSColor(calibratedWhite: 1, alpha: 0.065).cgColor : NSColor.clear.cgColor
        button.layer?.borderWidth = isEnabled ? 1 : 0
        button.layer?.borderColor = isEnabled ? subtleStroke.cgColor : NSColor.clear.cgColor
        button.contentTintColor = isEnabled ? label : nil
    }

    static func applyDestructiveButtonChrome(to button: NSButton) {
        applyButtonChrome(to: button)
        button.contentTintColor = .systemRed

        guard isEnabled else { return }
        button.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        button.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.35).cgColor
    }
}

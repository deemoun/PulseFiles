import AppKit

enum LiquidGlassStyle {
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 8
    static let windowBackground = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.095, alpha: 1)
    static let panelFill = NSColor(calibratedWhite: 1.0, alpha: 0.045)
    static let panelStroke = NSColor(calibratedWhite: 1.0, alpha: 0.12)
    static let subtleStroke = NSColor(calibratedWhite: 1.0, alpha: 0.08)
    static let activeStroke = NSColor.systemBlue.withAlphaComponent(0.7)
    static let activeFill = NSColor.systemBlue.withAlphaComponent(0.16)
    static let label = NSColor(calibratedWhite: 0.9, alpha: 1)
    static let secondaryLabel = NSColor(calibratedWhite: 0.68, alpha: 1)

    static func applyPanelChrome(to view: NSView, radius: CGFloat = cornerRadius) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = panelFill.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = panelStroke.cgColor
    }

    static func applyButtonChrome(to button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = compactCornerRadius
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.065).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = subtleStroke.cgColor
        button.contentTintColor = label
    }
}

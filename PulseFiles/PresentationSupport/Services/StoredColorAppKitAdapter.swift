import AppKit
import PulseFilesModels

enum StoredColorAppKitAdapter {
    static func rgba(from color: NSColor) -> RGBAColor {
        var converted: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { converted = color.usingColorSpace(.deviceRGB) }
        let rgb = converted ?? color.usingColorSpace(.deviceRGB) ?? NSColor(deviceWhite: 0, alpha: 1)
        return RGBAColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent), alpha: Double(rgb.alphaComponent))
    }
    static func color(from rgba: RGBAColor) -> NSColor {
        NSColor(deviceRed: CGFloat(rgba.red), green: CGFloat(rgba.green), blue: CGFloat(rgba.blue), alpha: CGFloat(rgba.alpha))
    }
}

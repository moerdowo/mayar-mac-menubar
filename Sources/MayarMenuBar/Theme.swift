import AppKit

enum Theme {

    enum Appearance: String, Codable, CaseIterable {
        case light, dark, system

        var nsAppearance: NSAppearance? {
            switch self {
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            case .system: return nil
            }
        }
    }

    /// Dynamic NSColor that resolves at draw-time to the appropriate variant
    /// for the current effective appearance. Layer-backed views must call
    /// `.cgColor` inside `updateLayer()` so AppKit re-runs them on appearance
    /// changes.
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // Surface
    static let windowBg     = dyn(NSColor(srgbRed: 0xF7/255, green: 0xF8/255, blue: 0xFA/255, alpha: 1),
                                  NSColor(srgbRed: 0x14/255, green: 0x15/255, blue: 0x18/255, alpha: 1))
    static let headerBg     = dyn(.white,
                                  NSColor(srgbRed: 0x1C/255, green: 0x1D/255, blue: 0x21/255, alpha: 1))
    static let cardBg       = dyn(.white,
                                  NSColor(srgbRed: 0x22/255, green: 0x23/255, blue: 0x27/255, alpha: 1))
    static let cardBorder   = dyn(NSColor(srgbRed: 0xE5/255, green: 0xE7/255, blue: 0xEB/255, alpha: 1),
                                  NSColor(srgbRed: 0x33/255, green: 0x35/255, blue: 0x3A/255, alpha: 1))
    static let dividerLine  = dyn(NSColor(srgbRed: 0xEE/255, green: 0xEF/255, blue: 0xF2/255, alpha: 1),
                                  NSColor(srgbRed: 0x2A/255, green: 0x2B/255, blue: 0x2F/255, alpha: 1))

    // Balance card (light periwinkle / dark deep blue)
    static let balanceBgTop    = dyn(NSColor(srgbRed: 0xF1/255, green: 0xF4/255, blue: 0xFC/255, alpha: 1),
                                     NSColor(srgbRed: 0x1F/255, green: 0x24/255, blue: 0x33/255, alpha: 1))
    static let balanceBgBot    = dyn(NSColor(srgbRed: 0xE8/255, green: 0xEC/255, blue: 0xF8/255, alpha: 1),
                                     NSColor(srgbRed: 0x18/255, green: 0x1D/255, blue: 0x2C/255, alpha: 1))
    static let balanceBorder   = dyn(NSColor(srgbRed: 0xDC/255, green: 0xE0/255, blue: 0xF0/255, alpha: 1),
                                     NSColor(srgbRed: 0x33/255, green: 0x39/255, blue: 0x4A/255, alpha: 1))

    // Text
    static let textPrimary     = dyn(NSColor(srgbRed: 0x11/255, green: 0x18/255, blue: 0x27/255, alpha: 1),
                                     NSColor(srgbRed: 0xF3/255, green: 0xF5/255, blue: 0xF8/255, alpha: 1))
    static let textSecondary   = dyn(NSColor(srgbRed: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1),
                                     NSColor(srgbRed: 0x9B/255, green: 0xA1/255, blue: 0xAC/255, alpha: 1))
    static let textTertiary    = dyn(NSColor(srgbRed: 0x9C/255, green: 0xA3/255, blue: 0xAF/255, alpha: 1),
                                     NSColor(srgbRed: 0x6E/255, green: 0x74/255, blue: 0x80/255, alpha: 1))

    // Tabs / accents
    static let tabInactiveBg   = dyn(NSColor(srgbRed: 0xF3/255, green: 0xF4/255, blue: 0xF6/255, alpha: 1),
                                     NSColor(srgbRed: 0x2A/255, green: 0x2C/255, blue: 0x32/255, alpha: 1))
    static let accentBlue      = dyn(NSColor(srgbRed: 0x25/255, green: 0x63/255, blue: 0xEB/255, alpha: 1),
                                     NSColor(srgbRed: 0x60/255, green: 0x8B/255, blue: 0xF6/255, alpha: 1))
    static let accentBlueSoft  = dyn(NSColor(srgbRed: 0xEE/255, green: 0xF3/255, blue: 0xFF/255, alpha: 1),
                                     NSColor(srgbRed: 0x1C/255, green: 0x2A/255, blue: 0x4A/255, alpha: 1))

    static let paidGreen       = dyn(NSColor(srgbRed: 0x16/255, green: 0xA3/255, blue: 0x4A/255, alpha: 1),
                                     NSColor(srgbRed: 0x4A/255, green: 0xD8/255, blue: 0x7A/255, alpha: 1))
    static let paidGreenSoft   = dyn(NSColor(srgbRed: 0xEC/255, green: 0xFD/255, blue: 0xF3/255, alpha: 1),
                                     NSColor(srgbRed: 0x14/255, green: 0x2A/255, blue: 0x1F/255, alpha: 1))
    static let unpaidPink      = dyn(NSColor(srgbRed: 0xED/255, green: 0x1E/255, blue: 0x79/255, alpha: 1),
                                     NSColor(srgbRed: 0xF3/255, green: 0x60/255, blue: 0xA0/255, alpha: 1))
    static let unpaidPinkSoft  = dyn(NSColor(srgbRed: 0xFD/255, green: 0xEE/255, blue: 0xF5/255, alpha: 1),
                                     NSColor(srgbRed: 0x35/255, green: 0x16/255, blue: 0x26/255, alpha: 1))

    // Skeleton
    static let skeletonBg      = dyn(NSColor(srgbRed: 0xEC/255, green: 0xEE/255, blue: 0xF1/255, alpha: 1),
                                     NSColor(srgbRed: 0x33/255, green: 0x35/255, blue: 0x3A/255, alpha: 1))

    // Brand
    static let mayarBlue       = NSColor(srgbRed: 0x0C/255, green: 0x52/255, blue: 0xEF/255, alpha: 1)
    static let mayarPink       = NSColor(srgbRed: 0xED/255, green: 0x1E/255, blue: 0x79/255, alpha: 1)

    // Type
    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}

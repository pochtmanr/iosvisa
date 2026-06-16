import SwiftUI

/// Semantic color aliases — the monochrome ink-on-paper spine plus the status
/// hues, each resolving correctly in light and dark. Mirrors the `:root` /
/// `.dark` semantic layer in `tokens/colors.css`.
///
/// Usage: `Color.theme.ink`, `Color.theme.border`, `StatusHue.green.soft`, etc.
enum Theme {
    // MARK: Neutral spine (paper → ink)
    /// Page background.
    static let bg = Color.dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x0A0A0A))
    /// Raised surface / input fill.
    static let surface = Color.dynamic(light: Color(hex: 0xFAFAFA), dark: Color(hex: 0x141414))
    /// Secondary surface / chips.
    static let surface2 = Color.dynamic(light: Color(hex: 0xF0F0F0), dark: Color(hex: 0x1F1F1F))
    /// Primary text + solid fills.
    static let ink = Color.dynamic(light: Color(hex: 0x000000), dark: Color(hex: 0xF5F5F5))
    /// Secondary text.
    static let inkMuted = Color.dynamic(light: Color(hex: 0x666666), dark: Color(hex: 0xA1A1A1))
    /// Tertiary text / eyebrows / hints.
    static let inkSoft = Color.dynamic(light: Color(hex: 0x878787), dark: Color(hex: 0x737373))
    /// Text on ink fills.
    static let inkInverse = Color.dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x0A0A0A))
    /// Hairline dividers + card borders.
    static let border = Color.dynamic(light: Color(hex: 0xEAEAEA), dark: Color(hex: 0x2A2A2A))
    /// Permanently-dark bands (footer, CTA).
    static let footerBg = Color(hex: 0x0A0A0A)

    // MARK: Semantic aliases
    static let textStrong = ink
    static let textBody = inkMuted
    static let textSoft = inkSoft
    static let textInverse = inkInverse

    static let surfacePage = bg
    static let surfaceCard = bg
    static let surfaceRaised = surface
    static let surfaceSunken = surface2

    static let accent = ink
    static let accentContrast = inkInverse
}

/// The seven semantic status hues. Each exposes a solid fill (light surfaces the
/// 500 step, dark the 400 step) and a soft badge pair (tinted bg + readable fg).
enum StatusHue: String, CaseIterable {
    case green, teal, blue, yellow, orange, red, purple

    /// Solid fill for chips, dots, status bars.
    var solid: Color {
        switch self {
        case .green:  return .dynamic(light: Palette.green500, dark: Palette.green400)
        case .teal:   return .dynamic(light: Palette.teal500, dark: Palette.teal400)
        case .blue:   return .dynamic(light: Palette.blue500, dark: Palette.blue400)
        case .yellow: return .dynamic(light: Palette.yellow500, dark: Palette.yellow400)
        case .orange: return .dynamic(light: Palette.orange500, dark: Palette.orange400)
        case .red:    return .dynamic(light: Palette.red500, dark: Palette.red400)
        case .purple: return .dynamic(light: Palette.purple500, dark: Palette.purple400)
        }
    }

    /// Soft badge background (light = 50, dark = 900).
    var softBg: Color {
        switch self {
        case .green:  return .dynamic(light: Palette.green50, dark: Palette.green900)
        case .teal:   return .dynamic(light: Palette.teal50, dark: Palette.teal900)
        case .blue:   return .dynamic(light: Palette.blue50, dark: Palette.blue900)
        case .yellow: return .dynamic(light: Palette.yellow50, dark: Palette.yellow900)
        case .orange: return .dynamic(light: Palette.orange50, dark: Palette.orange900)
        case .red:    return .dynamic(light: Palette.red50, dark: Palette.red900)
        case .purple: return .dynamic(light: Palette.purple50, dark: Palette.purple900)
        }
    }

    /// Soft badge foreground (light = 700/800, dark = 300).
    var softFg: Color {
        switch self {
        case .green:  return .dynamic(light: Palette.green700, dark: Palette.green300)
        case .teal:   return .dynamic(light: Palette.teal700, dark: Palette.teal300)
        case .blue:   return .dynamic(light: Palette.blue700, dark: Palette.blue300)
        case .yellow: return .dynamic(light: Palette.yellow800, dark: Palette.yellow300)
        case .orange: return .dynamic(light: Palette.orange700, dark: Palette.orange300)
        case .red:    return .dynamic(light: Palette.red700, dark: Palette.red300)
        case .purple: return .dynamic(light: Palette.purple700, dark: Palette.purple300)
        }
    }
}

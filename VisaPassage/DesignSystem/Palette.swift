import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Raw, theme-independent hue scales (50 → 900), ported verbatim from the web
/// design system (`tokens/colors.css`). These hex values never change between
/// light and dark — the semantic `Theme` layer decides which step to surface.
///
/// Saturated color is reserved for visa-status semantics only. For neutral ink,
/// surfaces, and borders use `Theme` (the semantic layer below).
enum Palette {
    // MARK: Green · visa-free / online / active
    static let green50 = Color(hex: 0xE6F5EC)
    static let green100 = Color(hex: 0xBCE3CB)
    static let green200 = Color(hex: 0x8FD0A8)
    static let green300 = Color(hex: 0x62BD85)
    static let green400 = Color(hex: 0x3FAF6B)
    static let green500 = Color(hex: 0x2EA85C)
    static let green600 = Color(hex: 0x228847)
    static let green700 = Color(hex: 0x186834)
    static let green800 = Color(hex: 0x0F4823)
    static let green900 = Color(hex: 0x082C14)

    // MARK: Teal · on-arrival / transit
    static let teal50 = Color(hex: 0xE4F5F6)
    static let teal100 = Color(hex: 0xB8E4E6)
    static let teal200 = Color(hex: 0x86D2D5)
    static let teal300 = Color(hex: 0x54BFC3)
    static let teal400 = Color(hex: 0x2FB1B6)
    static let teal500 = Color(hex: 0x14A2A8)
    static let teal600 = Color(hex: 0x0E8388)
    static let teal700 = Color(hex: 0x096368)
    static let teal800 = Color(hex: 0x054447)
    static let teal900 = Color(hex: 0x022B2D)

    // MARK: Blue · eVisa / informational
    static let blue50 = Color(hex: 0xE8F0FD)
    static let blue100 = Color(hex: 0xC5D9FA)
    static let blue200 = Color(hex: 0x9CBCF5)
    static let blue300 = Color(hex: 0x6F9CEF)
    static let blue400 = Color(hex: 0x4986EB)
    static let blue500 = Color(hex: 0x2E72E8)
    static let blue600 = Color(hex: 0x235AC4)
    static let blue700 = Color(hex: 0x184496)
    static let blue800 = Color(hex: 0x0F2E68)
    static let blue900 = Color(hex: 0x081C40)

    // MARK: Red · no admission / destructive / error
    static let red50 = Color(hex: 0xFDECEE)
    static let red100 = Color(hex: 0xFAC7CD)
    static let red200 = Color(hex: 0xF59CA6)
    static let red300 = Color(hex: 0xEF7180)
    static let red400 = Color(hex: 0xEC5263)
    static let red500 = Color(hex: 0xE83F4F)
    static let red600 = Color(hex: 0xC42D3C)
    static let red700 = Color(hex: 0x96202C)
    static let red800 = Color(hex: 0x68141D)
    static let red900 = Color(hex: 0x400B11)

    // MARK: Yellow · visa required / caution
    static let yellow50 = Color(hex: 0xFEF7E4)
    static let yellow100 = Color(hex: 0xFCEBB6)
    static let yellow200 = Color(hex: 0xFADC83)
    static let yellow300 = Color(hex: 0xF7CD50)
    static let yellow400 = Color(hex: 0xF5C42E)
    static let yellow500 = Color(hex: 0xF2BE14)
    static let yellow600 = Color(hex: 0xC99A0E)
    static let yellow700 = Color(hex: 0x9A7409)
    static let yellow800 = Color(hex: 0x6B4F05)
    static let yellow900 = Color(hex: 0x412F02)

    // MARK: Orange · pending / processing / warning
    static let orange50 = Color(hex: 0xFEF0E4)
    static let orange100 = Color(hex: 0xFCD6B6)
    static let orange200 = Color(hex: 0xFAB983)
    static let orange300 = Color(hex: 0xF79B50)
    static let orange400 = Color(hex: 0xF5882E)
    static let orange500 = Color(hex: 0xF2790E)
    static let orange600 = Color(hex: 0xC9620B)
    static let orange700 = Color(hex: 0x9A4907)
    static let orange800 = Color(hex: 0x6B3204)
    static let orange900 = Color(hex: 0x411E02)

    // MARK: Purple · premium / VIP accents
    static let purple50 = Color(hex: 0xF1ECFD)
    static let purple100 = Color(hex: 0xD8C7FA)
    static let purple200 = Color(hex: 0xBC9CF5)
    static let purple300 = Color(hex: 0x9F71EF)
    static let purple400 = Color(hex: 0x8D52EB)
    static let purple500 = Color(hex: 0x7C46E8)
    static let purple600 = Color(hex: 0x632DC4)
    static let purple700 = Color(hex: 0x4A2096)
    static let purple800 = Color(hex: 0x321468)
    static let purple900 = Color(hex: 0x1E0B40)
}

extension Color {
    /// Build a Color from a 0xRRGGBB integer literal.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// A color that resolves differently in light vs dark mode.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        return light
        #endif
    }
}

/// The world map's own palette, ported from the web hero checker (`--map-*`
/// and `--status-unknown` in `web/src/app/globals.css`, light then dark). Read
/// only by the map, its legend and the Explore filter chips; everything else
/// uses `StatusHue`.
enum MapPalette {
    static let free = Color.dynamic(light: Color(hex: 0x4E82E5), dark: Color(hex: 0x4170CB))
    static let arrival = Color.dynamic(light: Color(hex: 0x88AEF4), dark: Color(hex: 0x799BDA))
    static let evisa = Color.dynamic(light: Color(hex: 0xBFD7FF), dark: Color(hex: 0xAFC3E7))
    static let required = Color.dynamic(light: Color(hex: 0xF6D06A), dark: Color(hex: 0xD2AC4E))
    static let banned = Color.dynamic(light: Color(hex: 0xE9A09D), dark: Color(hex: 0xC37C79))
    /// No data.
    static let unknown = Color.dynamic(light: Color(hex: 0xEEF1F6), dark: Color(hex: 0x1E293B))
    /// Selected destination outline.
    static let focus = Color(hex: 0x2967E5)
    /// The passport holder's own country.
    static let home = Color.dynamic(light: Color(hex: 0x1E3A8A), dark: Color(hex: 0x3B5BB5))
    /// Country borders.
    static let border = Color.dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x0A0A0A))
    /// The sea under the land (web `--map-ocean`).
    static let ocean = Color.dynamic(light: Color(hex: 0xF7F9FC), dark: Color(hex: 0x0E1116))
}

/// Route-coverage ramps for the non-travel purposes (`--route-{purpose}-*` in
/// `web/src/app/globals.css`, light then dark; the dark steps are the web's
/// `color-mix(in oklab, …)` resolved to hex). One hue per purpose, so each
/// reads as its own map. Depth = distinct visa types the destination publishes
/// for the purpose: 1, 2, 3+. Never used for entry status.
enum RoutePalette {
    /// Ramp steps 1…3, then the focus (selected destination, accent).
    private struct Ramp {
        let light: [UInt32]
        let dark: [UInt32]
    }

    private static func ramp(_ purpose: Purpose) -> Ramp? {
        switch purpose {
        case .travel: return nil
        case .study: return Ramp(light: [0xD9CCFB, 0xB39AF5, 0x8B67EA, 0x6D3FE0],
                                 dark: [0x332A51, 0x524087, 0x7659C6, 0xA087F1])
        case .work: return Ramp(light: [0xB8E6DF, 0x7BCFC3, 0x3FB2A3, 0x14897B],
                                dark: [0x213F3A, 0x2D685F, 0x39978B, 0x6FC2B5])
        case .remote: return Ramp(light: [0xC5E4F7, 0x8CCBF0, 0x4FADE6, 0x1F86C7],
                                  dark: [0x243E4F, 0x346584, 0x4693C3, 0x77BEEC])
        case .immigrate: return Ramp(light: [0xC3EBD2, 0x86D3A5, 0x47B678, 0x1E8E50],
                                     dark: [0x22402E, 0x316A48, 0x3F9B67, 0x73C592])
        case .invest: return Ramp(light: [0xF6E3A8, 0xECC95F, 0xD9A82A, 0xB8860B],
                                  dark: [0x4B3C1C, 0x7D6324, 0xB88F29, 0xE1BA63])
        case .family: return Ramp(light: [0xF9D0C4, 0xF2A68F, 0xE67A5C, 0xD1532F],
                                  dark: [0x502F26, 0x854A39, 0xC36950, 0xEE967D])
        }
    }

    private static func step(_ purpose: Purpose, _ index: Int) -> Color {
        guard let r = ramp(purpose) else { return MapPalette.free }
        return .dynamic(light: Color(hex: r.light[index]), dark: Color(hex: r.dark[index]))
    }

    /// Ramp step 1…3 (`--route-{purpose}-{n}`).
    static func depth(_ n: Int, _ purpose: Purpose) -> Color {
        step(purpose, min(max(n, 1), 3) - 1)
    }

    /// `routeFillFor`: the fill for a destination with `typeCount` distinct visa types.
    static func fill(typeCount: Int, purpose: Purpose) -> Color {
        depth(typeCount, purpose)
    }

    /// `PURPOSE_ACCENT`: each purpose's map hue (glyphs, the focus outline).
    /// Travel speaks the travel map's visa-free focus blue.
    static func accent(_ purpose: Purpose) -> Color {
        purpose == .travel ? MapPalette.focus : step(purpose, 3)
    }

    /// Land with no route for the purpose (`--route-empty`).
    static let empty = Color.dynamic(light: Color(hex: 0xF2F2F2), dark: Color(hex: 0x171717))
    /// Its outline/strong step (`--route-empty-strong`).
    static let emptyStrong = Color.dynamic(light: Color(hex: 0xCACACA), dark: Color(hex: 0x303030))
}

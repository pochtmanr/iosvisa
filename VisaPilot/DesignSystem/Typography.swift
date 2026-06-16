import SwiftUI

/// Geist type scale ported from `tokens/typography.css`. Geist Sans for
/// everything, Geist Mono for numerals/labels. Headings use medium weight with
/// tight negative tracking; the wordmark uses semibold.
///
/// The point sizes are scaled down from the web pixel scale to native iOS
/// proportions (a 72px web hero ≈ 34pt large title on a phone).
enum Typography {
    enum Family {
        static let sans = "Geist"
        static let mono = "GeistMono"
    }

    /// Named font roles. `tracking` is in points (applied via `.tracking`).
    enum Role {
        case display, h1, h2, h3, title, bodyLg, body, sm, xs, eyebrow
        case monoBody, monoSm

        var size: CGFloat {
            switch self {
            case .display: return 34
            case .h1:      return 30
            case .h2:      return 26
            case .h3:      return 22
            case .title:   return 18
            case .bodyLg:  return 17
            case .body:    return 15
            case .sm:      return 14
            case .xs:      return 13
            case .eyebrow: return 11
            case .monoBody: return 15
            case .monoSm:  return 13
            }
        }

        var weight: Font.Weight {
            switch self {
            case .display, .h1, .h2, .h3, .title: return .medium
            case .bodyLg, .body, .sm, .xs, .monoBody, .monoSm: return .regular
            case .eyebrow: return .medium
            }
        }

        var fontName: String {
            switch self {
            case .monoBody, .monoSm:
                return weight == .medium ? "GeistMono-Medium" : "GeistMono-Regular"
            default:
                switch weight {
                case .medium:   return "Geist-Medium"
                case .semibold: return "Geist-SemiBold"
                default:        return "Geist-Regular"
                }
            }
        }

        /// Letter spacing in points (negative = tighter), from `--tracking-*`.
        var tracking: CGFloat {
            switch self {
            case .display: return -0.85   // -0.025em × 34
            case .h1, .h2, .h3: return -0.5
            case .eyebrow: return 2.0      // 0.18em uppercase
            default: return 0
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .display, .h1, .h2: return 2
            case .h3, .title: return 3
            case .bodyLg, .body: return 6  // ~1.55 leading
            default: return 2
            }
        }
    }

    static func font(_ role: Role) -> Font {
        .custom(role.fontName, size: role.size)
    }
}

extension View {
    /// Apply a VisaPilot type role (font + tracking + line spacing) in one call.
    func typography(_ role: Typography.Role) -> some View {
        self
            .font(Typography.font(role))
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }
}

extension Text {
    /// Convenience for inline `Text` styling that needs the font only.
    func typeRole(_ role: Typography.Role) -> Text {
        self.font(Typography.font(role)).tracking(role.tracking)
    }
}

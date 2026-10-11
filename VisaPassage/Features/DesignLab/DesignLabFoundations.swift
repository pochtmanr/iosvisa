#if DEBUG
import SwiftUI
import UIKit

// MARK: - Type ladder

struct LabTypeLadderPage: View {
    private static let rungs: [(name: String, role: Typography.Role, sample: String)] = [
        ("display", .display, "Where can you go?"),
        ("h1", .h1, "United Kingdom"),
        ("h2", .h2, "Entry requirements"),
        ("h3", .h3, "Documents you need"),
        ("title", .title, "Electronic Travel Authorisation"),
        ("bodyLg", .bodyLg, "Visa-free for up to 90 days in any 180-day period."),
        ("body", .body, "Apply online before you travel. Most decisions arrive within three working days."),
        ("sm", .sm, "Official authority decisions always prevail."),
        ("xs", .xs, "Updated 11 Oct 2026 · source: gov.uk"),
        ("eyebrow", .eyebrow, "PASSPORT STRENGTH"),
        ("monoBody", .monoBody, "GB → JP · 90 days"),
        ("monoSm", .monoSm, "£16 · 3 working days"),
    ]

    private static let fontNames = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"]

    var body: some View {
        LabNote("Every rung is drawn by .typography(role). Custom Geist sizes scale with Dynamic Type relative to body, so the slider button reflows this page. The caption is read from Typography.Role.")

        let missing = Self.fontNames.filter { UIFont(name: $0, size: 12) == nil }
        if !missing.isEmpty {
            LabDrift("Not registered, so these fall back to the system font: \(missing.joined(separator: ", "))")
        }

        ForEach(Self.rungs, id: \.name) { rung in
            LabSpecimen(title: rung.name, caption: caption(rung.role)) {
                Text(verbatim: rung.sample)
                    .typography(rung.role)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private func caption(_ role: Typography.Role) -> String {
        "\(role.fontName) · \(labNumber(role.size)) pt · tracking \(labNumber(role.tracking)) · line +\(labNumber(role.lineSpacing))"
    }
}

// MARK: - Colour

/// Resolves a token in a given appearance, for hex captions and contrast.
enum LabColor {
    static func rgba(_ color: Color, _ scheme: ColorScheme) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    static func hex(_ color: Color, _ scheme: ColorScheme) -> String {
        let c = rgba(color, scheme)
        let value = (Int((c.r * 255).rounded()) << 16) | (Int((c.g * 255).rounded()) << 8) | Int((c.b * 255).rounded())
        return String(format: "#%06X", value)
    }

    /// WCAG 2.x contrast ratio between two opaque colours.
    static func contrast(_ fg: Color, on bg: Color, _ scheme: ColorScheme) -> Double {
        let l1 = luminance(fg, scheme), l2 = luminance(bg, scheme)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func luminance(_ color: Color, _ scheme: ColorScheme) -> Double {
        let c = rgba(color, scheme)
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
}

/// A swatch painted in a forced appearance, with its resolved hex beneath.
struct LabSwatch: View {
    let color: Color
    let scheme: ColorScheme
    var height: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(color)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: Hairline.width)
                )
                .environment(\.colorScheme, scheme)
            Text(verbatim: LabColor.hex(color, scheme))
                .font(Typography.font(.monoSm))
                .foregroundStyle(Theme.textSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One named token in light and dark, side by side.
private struct LabTokenRow: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: name).typography(.sm).foregroundStyle(Theme.ink)
            HStack(spacing: Spacing.md) {
                LabSwatch(color: color, scheme: .light)
                LabSwatch(color: color, scheme: .dark)
            }
        }
    }
}

struct LabColourPage: View {
    private static let neutrals: [(String, Color)] = [
        ("Theme.bg · surfacePage · surfaceCard", Theme.bg),
        ("Theme.surface · surfaceRaised", Theme.surface),
        ("Theme.surface2 · surfaceSunken", Theme.surface2),
        ("Theme.ink · textStrong · accent", Theme.ink),
        ("Theme.inkMuted · textBody", Theme.inkMuted),
        ("Theme.inkSoft · textSoft", Theme.inkSoft),
        ("Theme.inkInverse · accentContrast", Theme.inkInverse),
        ("Theme.border", Theme.border),
        ("Theme.footerBg", Theme.footerBg),
    ]

    private static let textOnPaper: [(String, Color)] = [
        ("ink", Theme.ink), ("inkMuted", Theme.inkMuted), ("inkSoft", Theme.inkSoft),
    ]

    private static let ramps: [(String, [Color])] = [
        ("green", [Palette.green50, Palette.green100, Palette.green200, Palette.green300, Palette.green400, Palette.green500, Palette.green600, Palette.green700, Palette.green800, Palette.green900]),
        ("teal", [Palette.teal50, Palette.teal100, Palette.teal200, Palette.teal300, Palette.teal400, Palette.teal500, Palette.teal600, Palette.teal700, Palette.teal800, Palette.teal900]),
        ("blue", [Palette.blue50, Palette.blue100, Palette.blue200, Palette.blue300, Palette.blue400, Palette.blue500, Palette.blue600, Palette.blue700, Palette.blue800, Palette.blue900]),
        ("yellow", [Palette.yellow50, Palette.yellow100, Palette.yellow200, Palette.yellow300, Palette.yellow400, Palette.yellow500, Palette.yellow600, Palette.yellow700, Palette.yellow800, Palette.yellow900]),
        ("orange", [Palette.orange50, Palette.orange100, Palette.orange200, Palette.orange300, Palette.orange400, Palette.orange500, Palette.orange600, Palette.orange700, Palette.orange800, Palette.orange900]),
        ("red", [Palette.red50, Palette.red100, Palette.red200, Palette.red300, Palette.red400, Palette.red500, Palette.red600, Palette.red700, Palette.red800, Palette.red900]),
        ("purple", [Palette.purple50, Palette.purple100, Palette.purple200, Palette.purple300, Palette.purple400, Palette.purple500, Palette.purple600, Palette.purple700, Palette.purple800, Palette.purple900]),
    ]

    private static let map: [(String, Color)] = [
        ("free", MapPalette.free), ("arrival", MapPalette.arrival), ("evisa", MapPalette.evisa),
        ("required", MapPalette.required), ("banned", MapPalette.banned), ("unknown", MapPalette.unknown),
        ("focus", MapPalette.focus), ("home", MapPalette.home), ("border", MapPalette.border),
    ]

    var body: some View {
        LabNote("Monochrome ink on paper; saturated colour only for status. Left column light, right column dark, whatever the page appearance. Hexes are resolved from the tokens, not retyped.")

        LabSpecimen(title: "Neutral spine · Theme") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Self.neutrals, id: \.0) { LabTokenRow(name: $0.0, color: $0.1) }
            }
        }

        LabSpecimen(title: "Text contrast on Theme.bg", caption: "WCAG ratio · AA body text needs 4.5, large text 3.0") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.textOnPaper, id: \.0) { name, color in
                    HStack {
                        Text(verbatim: name).typography(.sm).foregroundStyle(Theme.ink)
                        Spacer()
                        contrastCell(color, .light)
                        contrastCell(color, .dark)
                    }
                }
            }
        }

        LabSpecimen(title: "Status hues · StatusHue", caption: "solid: light 500 / dark 400 · soft badge: light 50 + 700 / dark 900 + 300") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(StatusHue.allCases, id: \.self) { hue in
                    HStack(spacing: Spacing.md) {
                        Text(verbatim: hue.rawValue).typography(.sm).foregroundStyle(Theme.ink)
                            .frame(width: 64, alignment: .leading)
                        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                            HStack(spacing: Spacing.sm) {
                                StatusDot(hue: hue, size: 12)
                                StatusBadge(text: hue.rawValue, hue: hue)
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity)
                            .background(Theme.bg)
                            .environment(\.colorScheme, scheme)
                        }
                    }
                }
            }
        }

        LabSpecimen(title: "Raw ramps · Palette 50 → 900") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Self.ramps, id: \.0) { name, steps in
                    HStack(spacing: 2) {
                        Text(verbatim: name).typography(.xs).foregroundStyle(Theme.textBody)
                            .frame(width: 56, alignment: .leading)
                        ForEach(steps.indices, id: \.self) { index in
                            Rectangle().fill(steps[index]).frame(height: 24)
                        }
                    }
                }
            }
        }

        LabSpecimen(title: "Map · MapPalette", caption: "Read only by the map, its legend and the Explore filter chips.") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Self.map, id: \.0) { LabTokenRow(name: $0.0, color: $0.1) }
            }
        }
    }

    private func contrastCell(_ color: Color, _ scheme: ColorScheme) -> some View {
        let ratio = LabColor.contrast(color, on: Theme.bg, scheme)
        let hue: StatusHue = ratio >= 4.5 ? .green : ratio >= 3 ? .yellow : .red
        return Text(verbatim: "\(scheme == .dark ? "dark" : "light") \(String(format: "%.1f", ratio))")
            .font(Typography.font(.monoSm))
            .foregroundStyle(hue.softFg)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(hue.softBg, in: Capsule())
    }
}

// MARK: - Spacing & radii

struct LabGeometryPage: View {
    private static let spacing: [(String, CGFloat)] = [
        ("xs", Spacing.xs), ("sm", Spacing.sm), ("md", Spacing.md), ("lg", Spacing.lg),
        ("xl", Spacing.xl), ("xxl", Spacing.xxl), ("xxxl", Spacing.xxxl),
    ]

    private static let radii: [(String, CGFloat)] = [
        ("sm", Radius.sm), ("md", Radius.md), ("lg", Radius.lg), ("card", Radius.card), ("pill", Radius.pill),
    ]

    var body: some View {
        LabNote("Spacing, Radius and Hairline from Layout.swift. Hairline structure, 24 pt cards and no resting shadow are the brand's signature.")

        LabSpecimen(title: "Spacing") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Self.spacing, id: \.0) { name, value in
                    HStack(spacing: Spacing.md) {
                        Text(verbatim: name).font(Typography.font(.monoSm)).foregroundStyle(Theme.ink)
                            .frame(width: 44, alignment: .leading)
                        Rectangle().fill(Theme.ink).frame(width: value, height: 12)
                        Text(verbatim: "\(labNumber(value)) pt").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                    }
                }
            }
        }

        LabSpecimen(title: "Radius", caption: "All corners use .continuous (squircle) curvature.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(Self.radii, id: \.0) { name, value in
                    VStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: min(value, 32), style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: min(value, 32), style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
                            )
                            .frame(width: 72, height: 64)
                        Text(verbatim: "\(name) \(labNumber(value))").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                    }
                }
            }
        }

        LabSpecimen(title: "Hairline", caption: "Hairline.width \(labNumber(Hairline.width)) pt in Theme.border") {
            VStack(spacing: Spacing.md) {
                Rectangle().fill(Theme.border).frame(height: Hairline.width)
                Rectangle().fill(Theme.ink).frame(height: Hairline.width)
            }
        }
    }
}

// MARK: - Glyphs

struct LabGlyphsPage: View {
    /// Point sizes currently written as `.font(.system(size:))` literals in
    /// Features/ and DesignSystem/ (counted 2026-10-11). There is no glyph-size
    /// token yet; this list is what one would replace.
    private static let literalSizes: [CGFloat] = [9, 10.5, 11, 12, 13, 14, 15, 16, 20, 22, 28, 32]

    private static let catalogIcons: [(String, CatalogIcon)] = [
        ("calendar", .calendar), ("coin", .coin), ("hourglass", .hourglass), ("passport", .passport),
        ("zone", .zone), ("shieldClock", .shieldClock), ("building", .building), ("doc", .doc),
        ("check", .check), ("info", .info), ("stamp", .stamp), ("globe", .globe),
    ]

    var body: some View {
        LabDrift("No glyph-size token yet: screens size SF Symbols with \(Self.literalSizes.count) different literal point sizes. Pick a short ladder here, add it to Layout.swift, then sweep the screens.")

        LabSpecimen(title: "Literal sizes in use", caption: Self.literalSizes.map { labNumber($0) }.joined(separator: " · ") + " pt") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(Self.literalSizes, id: \.self) { size in
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: size, weight: .medium))
                            .frame(height: 36)
                        Text(verbatim: labNumber(size)).font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }

        LabSpecimen(title: "CatalogGlyph · fixed hue per meaning", caption: "These hues never mean entry status.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.md)], alignment: .leading, spacing: Spacing.md) {
                ForEach(Self.catalogIcons, id: \.0) { name, icon in
                    HStack(spacing: Spacing.sm) {
                        CatalogGlyph(icon: icon)
                        Text(verbatim: name).typography(.xs).foregroundStyle(Theme.textBody)
                    }
                }
            }
        }

        LabSpecimen(title: "CatalogGlyph · untinted") {
            HStack(spacing: Spacing.lg) {
                ForEach(Self.catalogIcons.prefix(6), id: \.0) { CatalogGlyph(icon: $0.1, tinted: false) }
            }
        }
    }
}
#endif

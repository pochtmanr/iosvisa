import SwiftUI

// SwiftUI ports of the landing's "How it works" illustrations
// (`web/src/components/landing/PassportCover.tsx`, `PassportFolder.tsx`, the
// `Chip` and `ChecklistSketch` in `HowItWorksSteps.tsx`, and `HeroStamps.tsx`).
// Geometry is taken from the SVG viewBoxes and scaled to the rendered size.
// All decorative: hidden from accessibility, since the page copy says it all.

// MARK: - Passport cover

/// Generic leather passport cover with gold-foil wordmark, globe and ePassport
/// chip. No national emblems. Drawn from the web's 176×248 viewBox.
struct PassportCover: View {
    enum Leather {
        case navy, burgundy, green

        var color: Color {
            switch self {
            case .navy: return Color(hex: 0x1D2853)
            case .burgundy: return Color(hex: 0x621A26)
            case .green: return Color(hex: 0x1C3A2C)
            }
        }
    }

    let leather: Leather

    private static let gold = Gradient(stops: [
        .init(color: Color(hex: 0xF6E6B6), location: 0),
        .init(color: Color(hex: 0xD6B36B), location: 0.32),
        .init(color: Color(hex: 0xB48C3E), location: 0.58),
        .init(color: Color(hex: 0xEFD9A0), location: 0.82),
        .init(color: Color(hex: 0xC49F52), location: 1),
    ])

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 176
            let full = CGRect(origin: .zero, size: size)
            let corner = 9 * s

            ctx.clip(to: Path(roundedRect: full, cornerRadius: corner, style: .continuous))
            ctx.fill(Path(full), with: .color(leather.color))

            // Embossed light: a diagonal sheen over the leather.
            ctx.fill(Path(full), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.16), location: 0),
                    .init(color: .white.opacity(0), location: 0.45),
                    .init(color: .black.opacity(0.28), location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

            // Spine shadow and its crease.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 13 * s, height: size.height)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.38), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.6),
                    .init(color: .white.opacity(0.06), location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 13 * s, y: 0)))
            var crease = Path()
            crease.move(to: CGPoint(x: 13 * s, y: 0))
            crease.addLine(to: CGPoint(x: 13 * s, y: size.height))
            ctx.stroke(crease, with: .color(.black.opacity(0.25)), lineWidth: 0.75 * s)

            // Deboss shadow first, then the foil on top.
            var shadow = ctx
            shadow.translateBy(x: 0, y: 0.8 * s)
            shadow.opacity = 0.45
            Self.drawFoil(in: shadow, scale: s, shading: .color(.black), textStyle: AnyShapeStyle(Color.black))

            let goldShading = GraphicsContext.Shading.linearGradient(
                Self.gold,
                startPoint: CGPoint(x: 40 * s, y: 40 * s),
                endPoint: CGPoint(x: 140 * s, y: 220 * s))
            Self.drawFoil(in: ctx, scale: s, shading: goldShading,
                          textStyle: AnyShapeStyle(LinearGradient(gradient: Self.gold, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .aspectRatio(176.0 / 248.0, contentMode: .fit)
        .overlay(
            // Cut-edge highlight.
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 9 * geo.size.width / 176, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
        )
        .accessibilityHidden(true)
    }

    private static func drawFoil(in ctx: GraphicsContext, scale s: CGFloat,
                                 shading: GraphicsContext.Shading, textStyle: AnyShapeStyle) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        func stroke(_ path: Path, _ width: CGFloat, opacity: Double = 1) {
            var c = ctx
            c.opacity *= opacity
            c.stroke(path, with: shading, style: StrokeStyle(lineWidth: width * s, lineCap: .round))
        }
        func ellipse(rx: CGFloat, ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (88 - rx) * s, y: (132 - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
        }

        // Wordmark (SVG baseline y = 68).
        let word = Text(verbatim: "PASSPORT")
            .font(.custom("Georgia", size: 15.5 * s))
            .tracking(3.2 * s)
            .foregroundStyle(textStyle)
        ctx.draw(word, at: p(88, 68), anchor: UnitPoint(x: 0.5, y: 0.78))

        // Globe.
        stroke(ellipse(rx: 31, ry: 31), 2.2)
        stroke(ellipse(rx: 37, ry: 37), 0.8, opacity: 0.7)
        stroke(ellipse(rx: 11, ry: 31), 1.3)
        stroke(ellipse(rx: 22, ry: 31), 1.3)
        var grid = Path()
        grid.move(to: p(88, 101)); grid.addLine(to: p(88, 163))
        grid.move(to: p(57, 132)); grid.addLine(to: p(119, 132))
        grid.move(to: p(61.2, 116.5)); grid.addLine(to: p(114.8, 116.5))
        grid.move(to: p(61.2, 147.5)); grid.addLine(to: p(114.8, 147.5))
        stroke(grid, 1.3)

        // ePassport chip symbol.
        stroke(Path(roundedRect: CGRect(x: 77 * s, y: 198 * s, width: 22 * s, height: 14 * s), cornerRadius: 2.5 * s), 1.5)
        var chip = Path()
        chip.move(to: p(77, 205)); chip.addLine(to: p(84.4, 205))
        chip.move(to: p(91.6, 205)); chip.addLine(to: p(99, 205))
        chip.addEllipse(in: CGRect(x: (88 - 3.6) * s, y: (205 - 3.6) * s, width: 7.2 * s, height: 7.2 * s))
        stroke(chip, 1.5)
    }
}

// MARK: - Passport folder

/// A Finder-style folder holding two passports (step 01 on the landing). The
/// web version fans the passports on hover; here they rise and fan once when
/// the page appears, and stay put under Reduce Motion.
struct PassportFolder: View {
    /// Rendered width; height follows the 136×96 viewBox.
    var width: CGFloat = 272
    /// Passports risen and fanned (the landing's hover state).
    var open: Bool

    var body: some View {
        let s = width / 136
        ZStack(alignment: .topLeading) {
            FolderBack()
                .fill(LinearGradient(colors: [Color(hex: 0xC9CCD1), Color(hex: 0xAEB2B8)], startPoint: .top, endPoint: .bottom))
                .overlay(FolderTabEdge().stroke(.white.opacity(0.38), lineWidth: 1))

            sheet(.burgundy, left: 30, rest: -3, lift: CGSize(width: -6, height: -18), fan: -8, s: s)
            sheet(.navy, left: 64, rest: 2, lift: CGSize(width: 6, height: -26), fan: 6, s: s)

            // Front panel: a touch shorter, tips forward when open.
            RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xE4E6E9), Color(hex: 0xC8CBD0)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().fill(.white.opacity(0.75)).frame(height: 1).padding(.horizontal, 6 * s)
                        Spacer().frame(height: 11.5 * s)
                        Rectangle().fill(Color(red: 40 / 255, green: 44 / 255, blue: 52 / 255).opacity(0.18))
                            .frame(height: 0.75).padding(.horizontal, 8 * s)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 2, y: -1)
                .frame(width: width, height: 68 * s)
                .rotation3DEffect(.degrees(open ? -16 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
                .offset(y: 28 * s)
        }
        .frame(width: width, height: 96 * s)
        .accessibilityHidden(true)
    }

    private func sheet(_ leather: PassportCover.Leather, left: CGFloat, rest: Double,
                       lift: CGSize, fan: Double, s: CGFloat) -> some View {
        PassportCover(leather: leather)
            .frame(width: 40 * s)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .rotationEffect(.degrees(open ? fan : rest), anchor: .bottom)
            .offset(x: (left + (open ? lift.width : 0)) * s, y: (10 + (open ? lift.height : 0)) * s)
    }
}

/// The folder's back panel with its tab, from the SVG path
/// `M0 7.5Q0 1.5 6 1.5H40Q44.5 1.5 47.2 5L50.5 9.5H130Q136 9.5 136 15.5V90Q136 96 130 96H6Q0 96 0 90Z`.
private struct FolderBack: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 136, sy = rect.height / 96
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(0, 7.5))
        path.addQuadCurve(to: p(6, 1.5), control: p(0, 1.5))
        path.addLine(to: p(40, 1.5))
        path.addQuadCurve(to: p(47.2, 5), control: p(44.5, 1.5))
        path.addLine(to: p(50.5, 9.5))
        path.addLine(to: p(130, 9.5))
        path.addQuadCurve(to: p(136, 15.5), control: p(136, 9.5))
        path.addLine(to: p(136, 90))
        path.addQuadCurve(to: p(130, 96), control: p(136, 96))
        path.addLine(to: p(6, 96))
        path.addQuadCurve(to: p(0, 90), control: p(0, 96))
        path.closeSubpath()
        return path
    }
}

/// Hairline highlight along the tab's top edge.
private struct FolderTabEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 136, sy = rect.height / 96
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(6, 2))
        path.addLine(to: p(40, 2))
        path.addQuadCurve(to: p(46.8, 5.4), control: p(44.2, 2))
        path.addLine(to: p(50.2, 10))
        path.addLine(to: p(130, 10))
        return path
    }
}

// MARK: - Status chip

/// The glass chip that floats over the landing photos: a mono label and a
/// route on top, then status rows.
struct StatusChip: View {
    enum Tone {
        case hue(StatusHue)
        case neutral
    }

    struct Row: Identifiable {
        let id = UUID()
        let label: LocalizedStringKey
        let status: LocalizedStringKey
        let tone: Tone
        var flag: String? = nil
    }

    let label: LocalizedStringKey
    let route: LocalizedStringKey
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text(label)
                    .font(.custom("GeistMono-Regular", size: 10.5))
                    .tracking(0.85)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
                Text(route)
                    .typography(.xs)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }

            VStack(spacing: Spacing.sm) {
                ForEach(rows) { row in
                    HStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.sm) {
                            if let flag = row.flag { CountryFlag(iso2: flag, size: 18) }
                            Text(row.label).typography(.xs).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        ChipBadge(text: row.status, tone: row.tone)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .background(Theme.bg.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: Hairline.width))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 12)
        .accessibilityHidden(true)
    }
}

/// Compact soft badge for the chip rows (sentence case, like the landing's).
private struct ChipBadge: View {
    let text: LocalizedStringKey
    let tone: StatusChip.Tone

    var body: some View {
        Text(text)
            .font(.custom("Geist-Medium", size: 11.5))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(fg)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private var fg: Color {
        if case .hue(let hue) = tone { return hue.softFg }
        return Theme.inkMuted
    }

    private var bg: Color {
        if case .hue(let hue) = tone { return hue.softBg }
        return Theme.surface2
    }
}

// MARK: - Checklist sketch

/// Step 03's checklist sketch: two ticked rows, one open, and an ink PDF tag.
struct ChecklistSketch: View {
    private let rows: [CGFloat] = [0.72, 0.58, 0.66]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, width in
                HStack(spacing: Spacing.md) {
                    ZStack {
                        if index < 2 {
                            Circle().fill(StatusHue.green.solid)
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .frame(width: 18, height: 18)
                    GeometryReader { geo in
                        Capsule().fill(Theme.ink.opacity(0.15)).frame(width: geo.size.width * width, height: 6)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 18)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: Hairline.width))
        .overlay(alignment: .topTrailing) {
            Text(verbatim: "PDF")
                .font(.custom("GeistMono-Medium", size: 10))
                .tracking(0.6)
                .foregroundStyle(Theme.inkInverse)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(x: -Spacing.lg, y: -10)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stamps

/// A passport stamp from the landing hero that "lands" once: it drops in from
/// a larger scale and settles at its tilt, after `delay`.
struct LandingStamp: View {
    let name: String
    let width: CGFloat
    let rotation: Double
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(landed ? 1 : 1.6)
            .opacity(landed ? 0.9 : 0)
            .onAppear {
                guard !landed else { return }
                if reduceMotion { landed = true; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(delay)) { landed = true }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color(hex: 0x1D2853).ignoresSafeArea()
        VStack(spacing: Spacing.xxl) {
            PassportFolder(open: true)
            StatusChip(label: "Example", route: "United States · Tourism", rows: [
                .init(label: "Italian passport", status: "Visa-free · 90 days", tone: .hue(.green), flag: "it"),
                .init(label: "Russian passport", status: "Visa required", tone: .hue(.red), flag: "ru"),
            ])
            .frame(width: 320)
            ChecklistSketch().frame(width: 240)
        }
    }
}

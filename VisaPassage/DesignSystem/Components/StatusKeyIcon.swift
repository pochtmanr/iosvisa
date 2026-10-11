import SwiftUI

/// The map key's duotone glyphs, ported from the web landing
/// (`DuoKeyIcon` in `components/landing/checker-stage/statusIcons.tsx`): a body
/// filled with the map colour and outlined in a deeper step of the same hue,
/// with detail lines on top. Drawn on the web's 24pt grid at its 1.6 stroke.
struct StatusKeyIcon: View {
    enum Glyph: Hashable {
        case status(VisaStatus)
        /// The passport holder's own country.
        case home
    }

    let glyph: Glyph
    var size: CGFloat = 16

    init(_ status: VisaStatus, size: CGFloat = 16) {
        glyph = .status(status)
        self.size = size
    }

    init(glyph: Glyph, size: CGFloat = 16) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        let tone = tone
        Canvas { context, canvas in
            let k = canvas.width / 24
            context.scaleBy(x: k, y: k)
            let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            let shape = Self.shape(for: glyph)
            context.fill(shape.body, with: .color(tone.fill))
            context.stroke(shape.body, with: .color(tone.stroke), style: style)
            context.stroke(shape.detail, with: .color(tone.detail), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Tones

    private struct Tone {
        var fill: Color
        var stroke: Color
        var detail: Color
    }

    /// Web `statusTone`: fill = map colour; stroke = the focus colour mixed 30%
    /// toward ink (`deep()`), precomputed per scheme. Visa-free's tick is white.
    private var tone: Tone {
        switch glyph {
        case .home:
            return Tone(fill: MapPalette.home, stroke: MapPalette.home, detail: .white)
        case .status(let status):
            switch status {
            case .visaFree:
                return Tone(fill: status.mapFill, stroke: Self.deepBlue, detail: .white)
            case .visaOnArrival, .evisa, .eta:
                return Tone(fill: status.mapFill, stroke: Self.deepBlue, detail: Self.deepBlue)
            case .visaRequired:
                return Tone(fill: status.mapFill, stroke: Self.deepAmber, detail: Self.deepAmber)
            case .noAdmission:
                return Tone(fill: status.mapFill, stroke: Self.deepRed, detail: Self.deepRed)
            case .unknown:
                return Tone(fill: MapPalette.unknown, stroke: Self.unknownStrong, detail: Theme.inkSoft)
            }
        }
    }

    private static let deepBlue = Color.dynamic(light: Color(hex: 0x1D48A0), dark: Color(hex: 0x6692EA))
    private static let deepAmber = Color.dynamic(light: Color(hex: 0xA87F0E), dark: Color(hex: 0xF2C958))
    private static let deepRed = Color.dynamic(light: Color(hex: 0x9D3F3C), dark: Color(hex: 0xE68885))
    private static let unknownStrong = Color.dynamic(light: Color(hex: 0xCBD5E1), dark: Color(hex: 0x334155))

    // MARK: - Glyphs (24pt grid, same coordinates as the web SVGs)

    private static func shape(for glyph: Glyph) -> (body: Path, detail: Path) {
        switch glyph {
        case .home:
            return (
                polygon([(5.5, 10.2), (12, 4.7), (18.5, 10.2), (18.5, 19.5), (5.5, 19.5)]),
                polyline([(10, 19.5), (10, 15), (14, 15), (14, 19.5)])
            )
        case .status(let status):
            switch status {
            case .visaFree:
                // An open gate: a tick on a disc.
                return (disc, polyline([(8.2, 12.3), (10.8, 14.9), (15.8, 9.6)]))
            case .visaOnArrival:
                // A stamp landing on arrival.
                var body = polygon([(9, 4.5), (15, 4.5), (14, 10.5), (10, 10.5)])
                body.addRoundedRect(in: CGRect(x: 5.5, y: 13.5, width: 13, height: 4),
                                    cornerSize: CGSize(width: 1, height: 1))
                return (body, polyline([(7, 20.5), (17, 20.5)]))
            case .evisa:
                // A screen: applied online.
                var detail = polyline([(8.5, 20), (15.5, 20)])
                detail.addPath(polyline([(9.5, 10.5), (11.5, 12.5), (15, 9)]))
                return (rounded(3.5, 4.5, 17, 12, r: 2), detail)
            case .eta:
                // A quick pre-travel authorisation.
                return (rounded(5, 3.5, 14, 17, r: 2.5),
                        polyline([(12.5, 7.5), (10, 12), (14, 12), (11.5, 16.5)]))
            case .visaRequired:
                // A passport page that needs a visa.
                var detail = Path(ellipseIn: CGRect(x: 9, y: 7.5, width: 6, height: 6))
                detail.addPath(polyline([(9, 16.5), (15, 16.5)]))
                return (rounded(5, 3.5, 14, 17, r: 2), detail)
            case .noAdmission:
                return (disc, polyline([(7, 17), (17, 7)]))
            case .unknown:
                return (disc, questionMark)
            }
        }
    }

    private static let disc = Path(ellipseIn: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))

    /// `M9.7 9.7a2.3 2.3 0 1 1 3.2 2.1c-.6.3-.9.8-.9 1.5v.4` plus the dot.
    private static let questionMark: Path = {
        var p = Path()
        let center = CGPoint(x: 12, y: 9.7), r = 2.3
        // Clockwise on screen from 180° round to ~67° (the large arc).
        let start = Double.pi, end = 2 * Double.pi + atan2(2.1, 0.9)
        let steps = 24
        for i in 0...steps {
            let a = start + (end - start) * Double(i) / Double(steps)
            let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.addCurve(to: CGPoint(x: 12, y: 13.3),
                   control1: CGPoint(x: 12.3, y: 12.1),
                   control2: CGPoint(x: 12, y: 12.6))
        p.addLine(to: CGPoint(x: 12, y: 13.7))
        p.move(to: CGPoint(x: 12, y: 16.6))
        p.addLine(to: CGPoint(x: 12.01, y: 16.6))
        return p
    }()

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .circular)
    }

    private static func polyline(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        return p
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = polyline(points)
        p.closeSubpath()
        return p
    }
}

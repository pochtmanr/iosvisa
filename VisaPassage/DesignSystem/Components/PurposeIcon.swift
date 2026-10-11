import SwiftUI

/// The purpose line glyphs, ported path for path from the web
/// (`PURPOSE_ICONS` in `web/src/components/landing/checker-stage/purposeIcons.tsx`):
/// a 24-unit grid, 1.5 stroke, round caps and joins (the house style). Not SF
/// Symbols, so the cards draw the same marks as the landing and the dashboard.
struct PurposeGlyph: Shape {
    let purpose: Purpose

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let unit = Self.unitPath(purpose)
        return unit.applying(
            CGAffineTransform(translationX: rect.minX + (rect.width - 24 * scale) / 2,
                              y: rect.minY + (rect.height - 24 * scale) / 2)
                .scaledBy(x: scale, y: scale)
        )
    }

    // swiftlint:disable:next function_body_length
    static func unitPath(_ purpose: Purpose) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func line(_ points: [CGPoint], close: Bool = false) {
            guard let first = points.first else { return }
            p.move(to: first)
            for q in points.dropFirst() { p.addLine(to: q) }
            if close { p.closeSubpath() }
        }
        switch purpose {
        case .travel:
            // M10.5 13.5 4 11l1.5-1.5 7 .5 4-4a1.8 1.8 0 0 1 2.5 2.5l-4 4 .5 7L14 21
            // l-2.5-6.5L8 18v2.5L6.5 22 5 19l-3-1.5L3.5 16H6l4.5-2.5Z
            p.move(to: pt(10.5, 13.5))
            p.addLine(to: pt(4, 11))
            p.addLine(to: pt(5.5, 9.5))
            p.addLine(to: pt(12.5, 10))
            p.addLine(to: pt(16.5, 6))
            // The nose: a 1.8 arc from (16.5, 6) to (19, 8.5), clockwise on screen.
            p.addRelativeArc(center: pt(17.5102, 7.4898), radius: 1.8,
                             startAngle: .degrees(-124.14), delta: .degrees(158.28))
            p.addLine(to: pt(15, 12.5))
            p.addLine(to: pt(15.5, 19.5))
            p.addLine(to: pt(14, 21))
            p.addLine(to: pt(11.5, 14.5))
            p.addLine(to: pt(8, 18))
            p.addLine(to: pt(8, 20.5))
            p.addLine(to: pt(6.5, 22))
            p.addLine(to: pt(5, 19))
            p.addLine(to: pt(2, 17.5))
            p.addLine(to: pt(3.5, 16))
            p.addLine(to: pt(6, 16))
            p.closeSubpath()
        case .study:
            line([pt(2.5, 9), pt(12, 4.5), pt(21.5, 9), pt(12, 13.5)], close: true)
            p.move(to: pt(6.5, 11))
            p.addLine(to: pt(6.5, 15.5))
            p.addCurve(to: pt(12, 18.5), control1: pt(6.5, 16.9), control2: pt(9, 18.5))
            p.addCurve(to: pt(17.5, 15.5), control1: pt(15, 18.5), control2: pt(17.5, 16.9))
            p.addLine(to: pt(17.5, 11))
            line([pt(21.5, 9), pt(21.5, 14)])
        case .work:
            p.addRoundedRect(in: CGRect(x: 3, y: 7.5, width: 18, height: 12.5),
                             cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: pt(8.5, 7.5))
            p.addLine(to: pt(8.5, 6))
            p.addArc(tangent1End: pt(8.5, 4), tangent2End: pt(10.5, 4), radius: 2)
            p.addLine(to: pt(13.5, 4))
            p.addArc(tangent1End: pt(15.5, 4), tangent2End: pt(15.5, 6), radius: 2)
            p.addLine(to: pt(15.5, 7.5))
            line([pt(3, 12.5), pt(21, 12.5)])
        case .remote:
            p.addRoundedRect(in: CGRect(x: 4, y: 5, width: 16, height: 10.5),
                             cornerSize: CGSize(width: 1.5, height: 1.5))
            line([pt(2.5, 19), pt(21.5, 19)])
            line([pt(9.5, 10.25), pt(14.5, 10.25)])
        case .immigrate:
            line([pt(4, 20.5), pt(4, 10), pt(12, 4), pt(20, 10), pt(20, 20.5)])
            line([pt(9.5, 20.5), pt(9.5, 14.5), pt(14.5, 14.5), pt(14.5, 20.5)])
        case .invest:
            line([pt(3.5, 17.5), pt(9, 12), pt(12.5, 15.5), pt(20.5, 7.5)])
            line([pt(15, 7.5), pt(20.5, 7.5), pt(20.5, 13)])
        case .family:
            p.addEllipse(in: CGRect(x: 5.5, y: 5, width: 5, height: 5))
            p.addEllipse(in: CGRect(x: 14.5, y: 7, width: 4, height: 4))
            p.move(to: pt(3.5, 19.5))
            p.addCurve(to: pt(8, 14.5), control1: pt(3.5, 16.5), control2: pt(5.5, 14.5))
            p.addCurve(to: pt(12.5, 19.5), control1: pt(10.5, 14.5), control2: pt(12.5, 16.5))
            p.move(to: pt(13, 19.5))
            p.addCurve(to: pt(16.5, 15.5), control1: pt(13.2, 17.1), control2: pt(14.6, 15.5))
            p.addCurve(to: pt(20, 19.5), control1: pt(18.4, 15.5), control2: pt(20, 17.1))
        }
        return p
    }
}

/// A purpose glyph at `size`, stroked in the current foreground style.
struct PurposeIcon: View {
    let purpose: Purpose
    var size: CGFloat = 16

    var body: some View {
        PurposeGlyph(purpose: purpose)
            .stroke(style: StrokeStyle(lineWidth: 1.5 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Spacing.lg) {
        ForEach(Purpose.allCases) { p in
            PurposeIcon(purpose: p, size: 32).foregroundStyle(RoutePalette.accent(p))
        }
    }
    .padding()
}

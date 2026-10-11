import SwiftUI

/// Where a country's pin stands, plane space. Hand-placed (lon, lat) for the
/// countries whose centroid lands somewhere odd (overseas territories, huge or
/// archipelago states), else the centroid of the largest landmass. The web's
/// `MANUAL_ANCHORS` (`web/src/components/map/atlas.ts`), kept in step.
enum MapAnchors {
    static let manual: [String: (lon: Double, lat: Double)] = [
        "US": (-98.5, 39.5), "CA": (-101, 56.5), "FR": (2.5, 46.6), "RU": (60, 58.5),
        "NO": (9.5, 61.3), "NL": (5.6, 52.2), "GB": (-1.8, 52.8), "CN": (104, 34.5),
        "NZ": (175.2, -39.2), "DK": (9.3, 56.1), "ES": (-3.7, 40.2), "PT": (-8.1, 39.7),
        "IT": (12.6, 42.9), "GR": (22, 39.4), "HR": (15.7, 45.4), "CL": (-71, -34),
        "AR": (-64.5, -34.5), "AU": (134, -25), "ID": (113.5, -1.5), "PH": (122.3, 12.5),
        "JP": (138.3, 36.3), "MY": (102, 4.2), "IN": (79, 22.5), "BR": (-51, -10),
        "EC": (-78.4, -1.5), "YE": (47.5, 15.5), "EG": (30.2, 26.6), "KI": (-157.4, 1.9),
        "FJ": (178, -17.8),
    ]

    static func manualPoint(_ iso2: String) -> CGPoint? {
        manual[iso2.uppercased()].map { MillerProjection.project(lonDeg: $0.lon, latDeg: $0.lat) }
    }
}

/// A teardrop map pin holding the country's circle flag, tip on the anchor,
/// with a soft ground shadow (web `FlagPin`). Constant size at every zoom: it
/// lives over the map, not inside its transform.
struct MapFlagPin: View {
    let iso2: String
    let tint: Color

    static let width: CGFloat = 30
    static let height: CGFloat = 38

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(.black.opacity(0.22))
                .frame(width: 12, height: 4)
                .blur(radius: 1.2)
                .offset(y: 2)
            ZStack(alignment: .top) {
                PinShape()
                    .fill(tint)
                    .overlay(PinShape().stroke(Theme.bg, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
                Circle()
                    .fill(Theme.bg)
                    .frame(width: 24, height: 24)
                    .padding(.top, 3)
                CountryFlag(iso2: iso2, size: 20)
                    .padding(.top, 5)
            }
            .frame(width: Self.width, height: Self.height)
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityHidden(true)
    }
}

/// Round head, tapering to a point at the bottom centre.
private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let cx = rect.midX
        let cy = rect.minY + r
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.minX, y: cy),
                   control1: CGPoint(x: cx - r * 0.35, y: rect.maxY - (rect.maxY - cy) * 0.35),
                   control2: CGPoint(x: rect.minX, y: cy + r * 0.75))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: cx, y: rect.maxY),
                   control1: CGPoint(x: rect.maxX, y: cy + r * 0.75),
                   control2: CGPoint(x: cx + r * 0.35, y: rect.maxY - (rect.maxY - cy) * 0.35))
        p.closeSubpath()
        return p
    }
}

/// The curved route from origin to destination (web `RouteArc`): a quadratic
/// bowed up and away from the straight line, on a halo so it reads over any
/// fill. Screen space, recomputed as the map moves.
struct RouteArcShape: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in _: CGRect) -> Path {
        var p = Path()
        let dx = to.x - from.x, dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 2 else { return p }
        // Normal to the chord, turned to point up, then tilted further up.
        var nx = dy / len, ny = -dx / len
        if ny > 0 || (ny == 0 && nx > 0) { nx = -nx; ny = -ny }
        let bx = nx * 0.5, by = ny * 0.5 - 0.5
        let bl = hypot(bx, by)
        let lift = min(90, max(6, len * 0.18))
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let control = CGPoint(x: mid.x + bx / bl * lift * 2, y: mid.y + by / bl * lift * 2)
        p.move(to: from)
        p.addQuadCurve(to: to, control: control)
        return p
    }
}

/// The arc, drawn on once when a route appears.
struct RouteArcView: View {
    let from: CGPoint
    let to: CGPoint
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RouteArcShape(from: from, to: to)
        ZStack {
            shape.trim(from: 0, to: drawn)
                .stroke(Theme.bg.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            shape.trim(from: 0, to: drawn)
                .stroke(Theme.ink.opacity(0.72), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeInOut(duration: 0.9).delay(0.35)) { drawn = 1 }
            }
        }
    }
}

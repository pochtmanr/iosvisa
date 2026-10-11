import SwiftUI

/// The floating-card backdrop for the welcome screen. A curated, decorative
/// scatter of destination cards (flag + name only — no visa status, since no
/// passport is selected before sign-in). Renders instantly from a static list,
/// with a gentle perpetual float for life. The bottom fades into the page so the
/// headline and auth sheet read cleanly on top.
struct DestinationCollage: View {
    /// A card's relative placement. `x`/`y` are fractions of the available size
    /// so the scatter scales across devices.
    private struct Placement: Identifiable {
        let id = UUID()
        let iso2: String
        let name: String
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
        let scale: CGFloat
        let opacity: Double
        /// Staggers the float so cards don't bob in unison.
        let phase: Double
    }

    /// Hand-tuned to mirror the reference collage: denser up top, thinning toward
    /// the headline. Marquee destinations, recognisable flags.
    private static let placements: [Placement] = [
        .init(iso2: "JP", name: "Japan",     x: 0.24, y: 0.10, rotation: -6, scale: 1.00, opacity: 1.00, phase: 0.0),
        .init(iso2: "IT", name: "Italy",     x: 0.72, y: 0.08, rotation:  5, scale: 0.92, opacity: 0.95, phase: 0.6),
        .init(iso2: "AE", name: "UAE",       x: 0.50, y: 0.20, rotation: -2, scale: 1.06, opacity: 1.00, phase: 1.2),
        .init(iso2: "FR", name: "France",    x: 0.14, y: 0.30, rotation:  7, scale: 0.88, opacity: 0.90, phase: 1.8),
        .init(iso2: "US", name: "USA",       x: 0.82, y: 0.28, rotation: -5, scale: 0.96, opacity: 0.95, phase: 0.3),
        .init(iso2: "TH", name: "Thailand",  x: 0.38, y: 0.38, rotation:  4, scale: 1.00, opacity: 1.00, phase: 2.1),
        .init(iso2: "BR", name: "Brazil",    x: 0.70, y: 0.44, rotation: -7, scale: 0.86, opacity: 0.88, phase: 0.9),
        .init(iso2: "AU", name: "Australia", x: 0.20, y: 0.50, rotation:  3, scale: 0.90, opacity: 0.90, phase: 1.5),
        .init(iso2: "ES", name: "Spain",     x: 0.86, y: 0.54, rotation:  6, scale: 0.82, opacity: 0.82, phase: 2.4),
        .init(iso2: "SG", name: "Singapore", x: 0.52, y: 0.58, rotation: -4, scale: 0.94, opacity: 0.92, phase: 0.45),
    ]

    /// Drives the perpetual float.
    @State private var floating = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Self.placements) { p in
                    CollageCard(iso2: p.iso2, name: p.name)
                        .scaleEffect(p.scale)
                        .rotationEffect(.degrees(p.rotation))
                        .opacity(p.opacity)
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                        .offset(y: floating ? -8 : 8)
                        .animation(
                            .easeInOut(duration: 3.2)
                            .repeatForever(autoreverses: true)
                            .delay(p.phase),
                            value: floating
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Fade the lower portion into the page so headline / sheet sit cleanly.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
        .onAppear { floating = true }
    }
}

/// A single decorative collage card: big flag over a country name, in the
/// signature paper-card treatment. Fixed width so the scatter reads as cards.
private struct CollageCard: View {
    let iso2: String
    let name: String

    var body: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CountryFlag(iso2: iso2, size: 34)
                Text(name)
                    .typography(.title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
        }
        .frame(width: 150)
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        DestinationCollage()
    }
}

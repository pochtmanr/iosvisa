import SwiftUI

/// A country ready to render: its projected (plane-space) rings plus the
/// resolved fill role for the current passport selection.
private struct MapCountry: Sendable {
    let iso2: String?
    let name: String
    var planeRings: [[CGPoint]]
    var status: VisaStatus
    var isHome: Bool
    /// Rough plane-space area, used to hit-test smaller countries first.
    var area: Double
}

/// Loads + projects the world atlas once and recolors it as the passport
/// selection changes. Decoding/projection happen off the main actor.
@MainActor
@Observable
final class WorldMapModel {
    fileprivate private(set) var countries: [MapCountry] = []
    private(set) var bounds: PlaneBounds = .empty
    private(set) var loading = true
    private(set) var failed = false

    private var atlas: WorldAtlas?
    private var numericToCountry: [String: Country] = [:]

    /// Decode the atlas (once) and project every ring into plane space.
    func loadAtlasIfNeeded() async {
        guard atlas == nil else { return }
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try TopoJSON.load(resource: "world-atlas-50m")
            }.value
            atlas = decoded
        } catch {
            failed = true
            loading = false
        }
    }

    /// Recompute fills for the given catalog + passports + best-status map.
    func rebuild(catalog: [Country], passports: [String], statusByDest: [String: VisaStatus]) {
        guard let atlas else { return }
        if numericToCountry.isEmpty {
            for c in catalog {
                if let n = c.paddedNumeric { numericToCountry[n] = c }
            }
        }
        let homeNumerics = Set(
            passports.compactMap { iso in
                catalog.first { $0.iso2.caseInsensitiveCompare(iso) == .orderedSame }?.paddedNumeric
            }
        )

        var result: [MapCountry] = []
        var bbox = PlaneBounds.empty
        for (numeric, geometry) in atlas.countries {
            let country = numericToCountry[numeric]
            let iso2 = country?.iso2
            var planeRings: [[CGPoint]] = []
            var area = 0.0
            for ring in geometry.rings {
                var projected: [CGPoint] = []
                projected.reserveCapacity(ring.count)
                for coord in ring {
                    let p = EqualEarth.project(lonDeg: coord.lon, latDeg: coord.lat)
                    projected.append(p)
                    bbox.expand(p)
                }
                area += abs(Self.signedArea(projected))
                planeRings.append(projected)
            }
            let status = iso2.flatMap { statusByDest[$0.uppercased()] } ?? .unknown
            result.append(MapCountry(
                iso2: iso2,
                name: geometry.name,
                planeRings: planeRings,
                status: status,
                isHome: homeNumerics.contains(numeric),
                area: area
            ))
        }
        // Larger countries first so small ones paint (and hit-test) on top.
        countries = result.sorted { $0.area > $1.area }
        bounds = bbox
        loading = false
    }

    /// Hit-test a screen point; returns the ISO2 of the topmost country hit.
    func country(at point: CGPoint, fit: ProjectionFit) -> String? {
        // `countries` is largest-first; iterate reversed so small ones win.
        for country in countries.reversed() {
            guard let iso2 = country.iso2 else { continue }
            for ring in country.planeRings where ring.count > 2 {
                if Self.contains(point: point, ring: ring, fit: fit) { return iso2 }
            }
        }
        return nil
    }

    // MARK: - Geometry helpers

    private static func signedArea(_ pts: [CGPoint]) -> Double {
        guard pts.count > 2 else { return 0 }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return sum / 2
    }

    /// Even-odd ray cast in screen space.
    private static func contains(point: CGPoint, ring: [CGPoint], fit: ProjectionFit) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = fit.screen(ring[i])
            let pj = fit.screen(ring[j])
            if (pi.y > point.y) != (pj.y > point.y) {
                let slope = (point.y - pi.y) / (pj.y - pi.y)
                if point.x < pi.x + slope * (pj.x - pi.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// The shaded vector world map. Fills each country by the best visa status for
/// the selected passport(s); tapping a country opens its detail.
struct WorldMapView: View {
    let onSelect: (String) -> Void

    @Environment(DiscoverySelection.self) private var selection
    @Environment(CountryStore.self) private var catalog
    @State private var model = WorldMapModel()
    @State private var statusByDest: [String: VisaStatus] = [:]
    @State private var loadingStatuses = false

    private let visa = VisaRepository()

    var body: some View {
        Group {
            if model.failed {
                MapMessage(text: "Couldn't load the map. Pull to retry.")
            } else if model.loading || loadingStatuses {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mapCanvas
            }
        }
        .task { await model.loadAtlasIfNeeded(); await refresh() }
        .onChange(of: selection.selectedPassports) { Task { await refresh() } }
        .onChange(of: catalog.countries.count) { Task { await refresh() } }
    }

    private var mapCanvas: some View {
        GeometryReader { geo in
            let fit = ProjectionFit.fitting(bounds: model.bounds, into: geo.size, inset: 6)
            Canvas { context, _ in
                for country in model.countries {
                    var path = Path()
                    for ring in country.planeRings where ring.count > 2 {
                        path.move(to: fit.screen(ring[0]))
                        for p in ring.dropFirst() { path.addLine(to: fit.screen(p)) }
                        path.closeSubpath()
                    }
                    let fill = color(for: country)
                    context.fill(path, with: .color(fill), style: FillStyle(eoFill: true))
                    context.stroke(path, with: .color(Theme.bg), lineWidth: 0.4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let iso = model.country(at: value.location, fit: fit) {
                        onSelect(iso)
                    }
                }
            )
        }
        .background(Theme.surface)
    }

    private func color(for country: MapCountry) -> Color {
        if country.isHome { return Theme.ink }
        switch country.status {
        case .unknown: return Theme.surface2
        default: return country.status.hue.solid
        }
    }

    private func refresh() async {
        guard !catalog.countries.isEmpty else { return }
        loadingStatuses = true
        defer { loadingStatuses = false }
        if !selection.selectedPassports.isEmpty {
            statusByDest = (try? await visa.bestStatuses(passports: selection.selectedPassports)) ?? [:]
        } else {
            statusByDest = [:]
        }
        model.rebuild(
            catalog: catalog.countries,
            passports: selection.selectedPassports,
            statusByDest: statusByDest
        )
    }
}

private struct MapMessage: View {
    let text: String
    var body: some View {
        Text(text)
            .typography(.sm)
            .foregroundStyle(Theme.textBody)
            .multilineTextAlignment(.center)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

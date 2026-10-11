import SwiftUI

/// A country ready to render: its ISO2 (nil when the catalog has no match) and
/// its projected (plane-space) rings.
private struct MapCountry: Sendable {
    let iso2: String?
    let name: String
    var planeRings: [[CGPoint]]
    /// Rough plane-space area, used to hit-test smaller countries first.
    var area: Double
}

/// Loads and projects the world atlas once. Colours are resolved at draw time,
/// so a passport or filter change never re-projects. Decoding happens off the
/// main actor.
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

    /// Project every country once the atlas and the countries catalog are both
    /// in. Later calls are no-ops.
    func projectIfNeeded(catalog: [Country]) {
        guard let atlas, !catalog.isEmpty, countries.isEmpty else { return }
        for c in catalog {
            if let n = c.paddedNumeric { numericToCountry[n] = c }
        }

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
            result.append(MapCountry(
                iso2: iso2,
                name: geometry.name,
                planeRings: planeRings,
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
/// the selected passports, in the web hero map's palette. A status filter fades
/// non-matching countries to "no data". Tapping reports the country (or nil for
/// the ocean) to the parent, which shows the bottom panel. The passport page
/// passes its own `statuses` and `home` instead of the selected passports.
struct WorldMapView: View {
    var filter: ExploreFilter = .all
    var focused: String?
    /// Status per destination ISO2; nil reads the shared `RequirementsStore`.
    var statuses: [String: VisaStatus]? = nil
    /// Countries shaded as "your passport"; nil reads `PassportPreference`.
    var home: Set<String>? = nil
    let onTap: (String?) -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog
    @State private var model = WorldMapModel()

    var body: some View {
        Group {
            if model.failed {
                MapMessage(text: "Couldn't load the map. Pull to retry.")
            } else if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mapCanvas
            }
        }
        .task { await model.loadAtlasIfNeeded(); model.projectIfNeeded(catalog: catalog.countries) }
        .onChange(of: catalog.countries.count) { model.projectIfNeeded(catalog: catalog.countries) }
    }

    private var mapCanvas: some View {
        GeometryReader { geo in
            let fit = ProjectionFit.fitting(bounds: model.bounds, into: geo.size, inset: 6)
            // Read the observed state outside the Canvas closure so SwiftUI
            // redraws when it changes.
            let overrides = statuses
            let best = overrides == nil ? requirements.best : [:]
            let focused = focused?.uppercased()
            let home = self.home ?? Set(passports.passports)
            Canvas { context, _ in
                var focusPath: Path?
                for country in model.countries {
                    var path = Path()
                    for ring in country.planeRings where ring.count > 2 {
                        path.move(to: fit.screen(ring[0]))
                        for p in ring.dropFirst() { path.addLine(to: fit.screen(p)) }
                        path.closeSubpath()
                    }
                    let status = country.iso2.flatMap { iso in
                        overrides?[iso.uppercased()] ?? best[iso.uppercased()]?.status
                    } ?? .unknown
                    let isHome = country.iso2.map { home.contains($0.uppercased()) } ?? false
                    context.fill(path, with: .color(fill(status, isHome: isHome)), style: FillStyle(eoFill: true))
                    context.stroke(path, with: .color(MapPalette.border), lineWidth: 0.4)
                    if let iso = country.iso2, iso.uppercased() == focused { focusPath = path }
                }
                if let focusPath {
                    context.stroke(focusPath, with: .color(MapPalette.focus), lineWidth: 1.6)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    onTap(model.country(at: value.location, fit: fit))
                }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("World map"))
            .accessibilityHint(Text("Use the List view to browse destinations with VoiceOver."))
        }
        .background(Theme.surface)
    }

    private func fill(_ status: VisaStatus, isHome: Bool) -> Color {
        if isHome { return MapPalette.home }
        guard filter.matches(status) else { return MapPalette.unknown }
        return status.mapFill
    }
}

private struct MapMessage: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .typography(.sm)
            .foregroundStyle(Theme.textBody)
            .multilineTextAlignment(.center)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

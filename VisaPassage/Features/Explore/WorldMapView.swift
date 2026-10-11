import SwiftUI

/// One country, projected once into plane space (MillerProjection) and kept as
/// a ready-made path: drawing applies a single affine transform, so a redraw
/// never re-projects a point.
private struct MapCountry: @unchecked Sendable {
    let numeric: String
    var iso2: String?
    let name: String
    /// Every ring (even-odd, so lakes carve out), seam copies included.
    let path: Path
    /// The path's bounds, for a cheap hit-test reject.
    let box: CGRect
    /// The largest landmass's bounds: auto-zoom frames this, not a box
    /// spanning overseas territories.
    let mainBox: CGRect
    /// The largest landmass's centroid (the pin, unless hand-placed).
    let centroid: CGPoint
    /// Rough plane-space area: larger countries paint first, smaller hit first.
    let area: Double
}

/// Loads and projects the world atlas once, off the main actor. Colours are
/// resolved at draw time, so a passport or filter change never re-projects.
@MainActor
@Observable
final class WorldMapModel {
    fileprivate private(set) var countries: [MapCountry] = []
    /// Bumped when `countries` changes: the canvas compares it, not the array.
    fileprivate private(set) var revision = 0
    private(set) var loading = true
    private(set) var failed = false

    private var projected: [MapCountry]?
    private var attached = false

    /// Decode and project the atlas (once), both off the main actor.
    func loadAtlasIfNeeded() async {
        guard projected == nil, !failed else { return }
        do {
            projected = try await Task.detached(priority: .userInitiated) {
                Self.project(try TopoJSON.load(resource: "world-atlas-50m"))
            }.value
        } catch {
            failed = true
            loading = false
        }
    }

    /// Attach ISO2 codes once the atlas and the countries catalog are both in.
    /// Later calls are no-ops.
    func projectIfNeeded(catalog: [Country]) {
        guard let projected, !catalog.isEmpty, !attached else { return }
        var iso2ByNumeric: [String: String] = [:]
        for c in catalog {
            if let n = c.paddedNumeric { iso2ByNumeric[n] = c.iso2.uppercased() }
        }
        countries = projected.map { c in
            var c = c
            c.iso2 = iso2ByNumeric[c.numeric]
            return c
        }
        attached = true
        revision += 1
        loading = false
    }

    nonisolated private static let antarctica = "010"

    nonisolated private static func project(_ atlas: WorldAtlas) -> [MapCountry] {
        var result: [MapCountry] = []
        result.reserveCapacity(atlas.countries.count)
        for (numeric, geometry) in atlas.countries where numeric != antarctica {
            var path = Path()
            var area = 0.0
            var mainArea = -1.0
            var mainRing: [CGPoint] = []
            for ring in geometry.rings {
                for projected in MillerProjection.rings(for: ring) {
                    path.move(to: projected[0])
                    for p in projected.dropFirst() { path.addLine(to: p) }
                    path.closeSubpath()
                    let a = abs(signedArea(projected))
                    area += a
                    if a > mainArea { mainArea = a; mainRing = projected }
                }
            }
            guard !path.isEmpty else { continue }
            let mainPath = Path { p in p.addLines(mainRing) }
            result.append(MapCountry(
                numeric: numeric,
                iso2: nil,
                name: geometry.name,
                path: path,
                box: path.boundingRect,
                mainBox: mainPath.boundingRect,
                centroid: centroid(mainRing) ?? CGPoint(x: mainPath.boundingRect.midX, y: mainPath.boundingRect.midY),
                area: area
            ))
        }
        // Larger countries first so small ones paint (and hit-test) on top.
        return result.sorted { $0.area > $1.area }
    }

    /// Plane-space centre of these countries' main landmasses (your passports).
    func centre(of iso2s: Set<String>) -> CGPoint? {
        let boxes = countries.filter { $0.iso2.map(iso2s.contains) ?? false }.map(\.mainBox)
        guard let first = boxes.first else { return nil }
        let box = boxes.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// The main landmass bounds of one country.
    func mainBox(_ iso2: String) -> CGRect? {
        countries.first { $0.iso2 == iso2.uppercased() }?.mainBox
    }

    /// Where a country's pin stands (plane space).
    func anchor(_ iso2: String) -> CGPoint? {
        if let manual = MapAnchors.manualPoint(iso2) { return manual }
        return countries.first { $0.iso2 == iso2.uppercased() }?.centroid
    }

    /// Hit-test a screen point; returns the ISO2 of the topmost country hit.
    func country(at point: CGPoint, fit: ProjectionFit) -> String? {
        let p = fit.plane(point)
        // `countries` is largest-first; iterate reversed so small ones win.
        for country in countries.reversed() {
            guard let iso2 = country.iso2, country.box.contains(p) else { continue }
            if country.path.contains(p, eoFill: true) { return iso2 }
        }
        return nil
    }

    // MARK: - Geometry helpers

    nonisolated private static func signedArea(_ pts: [CGPoint]) -> Double {
        guard pts.count > 2 else { return 0 }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return sum / 2
    }

    nonisolated private static func centroid(_ pts: [CGPoint]) -> CGPoint? {
        let a = signedArea(pts)
        guard abs(a) > 1e-12 else { return nil }
        var cx = 0.0, cy = 0.0
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            let f = Double(p.x * q.y - q.x * p.y)
            cx += Double(p.x + q.x) * f
            cy += Double(p.y + q.y) * f
        }
        return CGPoint(x: cx / (6 * a), y: cy / (6 * a))
    }
}

/// The shaded vector world map. Fills each country by the best visa status for
/// the selected passports, in the web map's palette and projection. A status
/// filter fades non-matching countries to "no data". Tapping reports the
/// country (or nil for the ocean) to the parent, which shows the bottom panel.
/// The passport page passes its own `statuses` and `home` instead.
///
/// `interactive` (Explore) zooms like the web map: it opens filling the frame
/// on your passport; pinch, double-tap or + zooms in, − and fit zoom out, and
/// once zoomed in one finger pans (at fit it scrolls the page, and a sideways
/// drag still pans). A pick flies to frame the route, drops flag pins on both
/// ends and draws the arc between them.
///
/// Speed: the countries are drawn once per committed view into a GPU layer
/// (`MapLayer`, equatable, so a gesture frame never redraws it); gestures and
/// flies only transform that layer, and the pins ride on top at constant size.
struct WorldMapView: View {
    var filter: ExploreFilter = .all
    var focused: String?
    /// Status per destination ISO2; nil reads the shared `RequirementsStore`.
    var statuses: [String: VisaStatus]? = nil
    /// Countries shaded as "your passport"; nil reads `PassportPreference`.
    var home: Set<String>? = nil
    /// A route purpose's fills per destination ISO2 (`routeFillByNumeric`);
    /// land without one takes `RoutePalette.empty`. Nil paints entry status.
    var routeFills: [String: Color]? = nil
    /// The selected destination's outline (the purpose's focus hue).
    var focusColor: Color = MapPalette.focus
    var interactive = false
    let onTap: (String?) -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = WorldMapModel()
    /// The view drawn into the map layer (committed).
    @State private var viewport = MapViewport()
    /// The view on screen: equals `viewport` at rest, runs ahead of it during
    /// a gesture or a fly (the layer is transformed to it, then redrawn).
    @State private var shown = MapViewport()
    /// `shown` when the current pinch / drag began.
    @State private var gestureStart: MapViewport?
    @State private var placed = false
    @State private var flight = 0
    /// A fly is under way (the edge blur sits out moves, like the web's).
    @State private var flying = false

    private let window = MillerProjection.window

    var body: some View {
        ZStack {
            if model.failed {
                MapMessage(text: "Couldn't load the map. Pull to retry.")
            } else if model.loading {
                MapSkeleton()
                    .transition(.opacity)
            } else {
                mapCanvas
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.45), value: model.loading)
        .task { await model.loadAtlasIfNeeded(); model.projectIfNeeded(catalog: catalog.countries) }
        .onChange(of: catalog.countries.count) { model.projectIfNeeded(catalog: catalog.countries) }
    }

    private var mapCanvas: some View {
        GeometryReader { geo in
            if interactive {
                zoomableCanvas(size: geo.size)
            } else {
                let fit = ProjectionFit.fitting(bounds: window, into: geo.size, inset: 6)
                layer(fit: fit)
                    .gesture(SpatialTapGesture().onEnded { value in
                        onTap(model.country(at: value.location, fit: fit))
                    })
            }
        }
        .background(MapPalette.ocean)
    }

    // MARK: - Zoom

    private func zoomableCanvas(size: CGSize) -> some View {
        let base = MapViewport.coverFit(bounds: window, size: size)
        let drawn = viewport.fit(base)
        let onScreen = shown.fit(base)
        let zoomedIn = shown.k > 1.001
        let pinchPan = SimultaneousGesture(MagnifyGesture(), DragGesture(minimumDistance: 8))
            .onChanged { value in
                let start = gestureStart ?? shown
                if gestureStart == nil { gestureStart = shown }
                var next = start
                if let pinch = value.first {
                    next = next.zoomed(to: start.k * pinch.magnification, anchor: pinch.startLocation)
                }
                if let drag = value.second {
                    next.t.width += drag.translation.width
                    next.t.height += drag.translation.height
                }
                shown = next.clamped(bounds: window, size: size)
            }
            .onEnded { _ in
                gestureStart = nil
                flying = false
                viewport = shown
            }
        let taps = SpatialTapGesture(count: 2)
            .onEnded { value in
                fly(to: shown.zoomed(to: shown.k * 2, anchor: value.location), size: size)
            }
            .exclusively(before: SpatialTapGesture().onEnded { value in
                onTap(model.country(at: value.location, fit: onScreen))
            })
        let r = shown.k / viewport.k
        let dx = shown.t.width - r * viewport.t.width
        let dy = shown.t.height - r * viewport.t.height
        let moving = gestureStart != nil || flying
        return ZStack(alignment: .topLeading) {
            // Linear in the animation, like the pins' positions below, so the
            // two stay locked together through a fly.
            layer(fit: drawn)
                .scaleEffect(r, anchor: .topLeading)
                .offset(x: dx, y: dy)
            // Edge blur: a blurred copy of the same layer, shown only in a
            // band along the frame's edges, so land cut by the frame melts
            // into blur (a real blur, not a fade). At rest only: it hides for
            // every pan, pinch and fly frame.
            layer(fit: drawn)
                .blur(radius: 5)
                .scaleEffect(r, anchor: .topLeading)
                .offset(x: dx, y: dy)
                .mask(EdgeBand(size: size))
                .opacity(moving ? 0 : 1)
                .animation(.easeOut(duration: moving ? 0.08 : 0.3), value: moving)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            pins(fit: onScreen)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(taps)
        // Zoomed in, one finger pans the map; at fit the page keeps the
        // vertical scroll and a sideways drag pans the cropped sides.
        .modifier(PanPriority(gesture: pinchPan, exclusive: zoomedIn))
        .overlay(alignment: .bottomTrailing) {
            MapZoomControls(
                canZoomIn: shown.k < MapViewport.maxZoom - 0.001,
                canZoomOut: shown.k > MapViewport.minZoom(bounds: window, size: size) + 0.001,
                onZoomIn: { step(1.6, size: size) },
                onZoomOut: { step(1 / 1.6, size: size) },
                onFit: { fly(to: MapViewport(k: 0), size: size) }
            )
            .padding(Spacing.sm)
        }
        .task(id: PlaceKey(size: size, ready: !model.loading)) { place(size: size) }
        .onChange(of: focused) { frameRoute(size: size) }
    }

    private func step(_ factor: Double, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        fly(to: shown.zoomed(to: shown.k * factor, anchor: centre), size: size, duration: 0.3)
    }

    /// Animate the view to `target`, then redraw the layer there (crisp).
    private func fly(to target: MapViewport, size: CGSize, duration: Double = 0.6) {
        let next = target.clamped(bounds: window, size: size)
        flight += 1
        let id = flight
        if reduceMotion {
            shown = next
            viewport = next
            return
        }
        flying = true
        withAnimation(.smooth(duration: duration)) {
            shown = next
        } completion: {
            // A newer fly or a gesture took over: it commits its own view.
            guard id == flight, gestureStart == nil else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { viewport = shown }
            flying = false
        }
    }

    /// A pick frames origin + destination (web auto-zoom); clearing it flies
    /// back to the opening view.
    private func frameRoute(size: CGSize) {
        guard placed else { return }
        guard let dest = focused?.uppercased(), let destBox = model.mainBox(dest) else {
            return fly(to: openingView(size: size), size: size)
        }
        var box = destBox
        if let origin = originIso2, origin != dest, let originBox = model.mainBox(origin) {
            box = box.union(originBox)
        }
        // Leave headroom for the pins standing above their anchors.
        let padded = box.insetBy(dx: -box.width * 0.08, dy: -box.height * 0.12)
        fly(to: MapViewport.fitting(padded, bounds: window, size: size, padding: 36), size: size, duration: 0.7)
    }

    private func openingView(size: CGSize) -> MapViewport {
        let base = MapViewport.coverFit(bounds: window, size: size)
        var start = MapViewport()
        if let centre = model.centre(of: homeSet) {
            start = start.centring(centre, base: base, size: size)
        }
        return start.clamped(bounds: window, size: size)
    }

    /// First layout: fill the frame and centre on your passports' countries
    /// (or frame the route, when the screen opens on a pick). Later size
    /// changes just re-clamp.
    private func place(size: CGSize) {
        guard !model.loading, size.width > 0 else { return }
        guard !placed else {
            let next = shown.clamped(bounds: window, size: size)
            shown = next
            viewport = next
            return
        }
        placed = true
        let start = openingView(size: size)
        shown = start
        viewport = start
        if focused != nil { frameRoute(size: size) }
    }

    // MARK: - Pins

    private var homeSet: Set<String> {
        Set((home ?? Set(passports.passports)).map { $0.uppercased() })
    }

    /// The pin at home: your first passport (the passport page: its country).
    private var originIso2: String? {
        if let home { return home.sorted().first?.uppercased() }
        return passports.passports.first?.uppercased()
    }

    @ViewBuilder
    private func pins(fit: ProjectionFit) -> some View {
        let origin = originIso2
        let dest = focused?.uppercased()
        let destPin = dest.flatMap { homeSet.contains($0) ? nil : $0 }
        let originPoint = origin.flatMap { model.anchor($0) }.map(fit.screen)
        let destPoint = destPin.flatMap { model.anchor($0) }.map(fit.screen)
        ZStack(alignment: .topLeading) {
            if let originPoint, let destPoint, let destPin {
                RouteArcView(from: originPoint, to: destPoint)
                    .id("arc-\(origin ?? "")-\(destPin)")
                    .transition(.opacity)
            }
            if let origin, let originPoint {
                pin(origin, at: originPoint, tint: MapPalette.home)
            }
            if let destPin, let destPoint {
                pin(destPin, at: destPoint, tint: Theme.ink)
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: destPin)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: origin)
    }

    private func pin(_ iso2: String, at point: CGPoint, tint: Color) -> some View {
        MapFlagPin(iso2: iso2, tint: tint)
            // Tip on the anchor.
            .position(x: point.x, y: point.y - MapFlagPin.height / 2)
            .id(iso2)
            .transition(
                .asymmetric(
                    insertion: .offset(y: -26).combined(with: .scale(scale: 0.6, anchor: .bottom)).combined(with: .opacity),
                    removal: .offset(y: -18).combined(with: .opacity)
                )
            )
    }

    // MARK: - Layer

    private func layer(fit: ProjectionFit) -> some View {
        // Read the observed state here (not inside the Canvas closure) so
        // SwiftUI redraws when it changes.
        let overrides = statuses
        let best = overrides == nil ? requirements.best : [:]
        let focused = focused?.uppercased()
        let home = homeSet
        var colors: [Color] = []
        colors.reserveCapacity(model.countries.count)
        var focusIndex: Int?
        for (i, country) in model.countries.enumerated() {
            let iso = country.iso2
            let isHome = iso.map(home.contains) ?? false
            if let routeFills {
                colors.append(isHome ? MapPalette.home : iso.flatMap { routeFills[$0] } ?? RoutePalette.empty)
            } else {
                let status = iso.flatMap { overrides?[$0] ?? best[$0]?.status } ?? .unknown
                colors.append(fill(status, isHome: isHome))
            }
            if let iso, iso == focused { focusIndex = i }
        }
        return MapLayer(
            countries: model.countries,
            revision: model.revision,
            colors: colors,
            focusIndex: focusIndex,
            focusColor: focusColor,
            fit: fit
        )
        .equatable()
        .accessibilityElement()
        .accessibilityLabel(Text("World map"))
        .accessibilityHint(Text("Destinations are listed below the map."))
    }

    private func fill(_ status: VisaStatus, isHome: Bool) -> Color {
        if isHome { return MapPalette.home }
        guard filter.matches(status) else { return MapPalette.unknown }
        return status.mapFill
    }
}

/// Every country, drawn once per committed view into a Metal-backed layer.
/// Equatable on its inputs, so the many body updates of a gesture or a fly
/// (which only move the layer) never redraw it.
private struct MapLayer: View, @MainActor Equatable {
    let countries: [MapCountry]
    let revision: Int
    let colors: [Color]
    let focusIndex: Int?
    let focusColor: Color
    let fit: ProjectionFit

    static func == (a: MapLayer, b: MapLayer) -> Bool {
        a.revision == b.revision && a.fit == b.fit && a.focusIndex == b.focusIndex
            && a.focusColor == b.focusColor && a.colors == b.colors
    }

    var body: some View {
        Canvas { context, _ in
            let window = MillerProjection.window
            let toScreen = fit.planeToScreen
            // The land window only: seam copies past it stay hidden.
            let windowRect = CGRect(x: window.minX, y: window.minY,
                                    width: window.maxX - window.minX,
                                    height: window.maxY - window.minY).applying(toScreen)
            context.clip(to: Path(windowRect))
            context.concatenate(toScreen)
            let px = 1 / fit.scale
            let border = MapPalette.border
            for (i, country) in countries.enumerated() where i < colors.count {
                context.fill(country.path, with: .color(colors[i]), style: FillStyle(eoFill: true))
                context.stroke(country.path, with: .color(border), lineWidth: 0.45 * px)
            }
            if let focusIndex, focusIndex < countries.count {
                let path = countries[focusIndex].path
                context.stroke(path, with: .color(focusColor.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 6 * px, lineJoin: .round))
                context.stroke(path, with: .color(focusColor),
                               style: StrokeStyle(lineWidth: 1.6 * px, lineJoin: .round))
            }
        }
        .drawingGroup()
    }
}

/// The band the edge blur shows through: opaque at the frame's edges, clear
/// a few points in, on every side.
private struct EdgeBand: View {
    let size: CGSize
    private let depth: CGFloat = 22

    var body: some View {
        let x = min(0.25, depth / max(1, size.width))
        let y = min(0.25, depth / max(1, size.height))
        ZStack {
            LinearGradient(stops: [
                .init(color: .black, location: 0), .init(color: .clear, location: x),
                .init(color: .clear, location: 1 - x), .init(color: .black, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .black, location: 0), .init(color: .clear, location: y),
                .init(color: .clear, location: 1 - y), .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .compositingGroup()
    }
}

/// While the atlas decodes: the frame's ocean with a slow light sweep.
private struct MapSkeleton: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            MapPalette.ocean
                .overlay {
                    LinearGradient(colors: [.clear, Theme.ink.opacity(0.05), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                }
                .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
        .accessibilityLabel(Text("Loading the map"))
    }
}

private struct PlaceKey: Hashable {
    let size: CGSize
    let ready: Bool
}

/// The pan/pinch gesture: exclusive once zoomed in (the list stops
/// scrolling under the finger), simultaneous with the scroll at fit.
private struct PanPriority<G: Gesture>: ViewModifier {
    let gesture: G
    let exclusive: Bool

    func body(content: Content) -> some View {
        if exclusive {
            content.highPriorityGesture(gesture)
        } else {
            content.simultaneousGesture(gesture)
        }
    }
}

/// +, − and fit, bottom-right of the map (web `MapControls`).
private struct MapZoomControls: View {
    let canZoomIn: Bool
    let canZoomOut: Bool
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            button("plus", label: "Zoom in", enabled: canZoomIn, action: onZoomIn)
            Rectangle().fill(Theme.border).frame(width: 20, height: Hairline.width)
            button("minus", label: "Zoom out", enabled: canZoomOut, action: onZoomOut)
            Rectangle().fill(Theme.border).frame(width: 20, height: Hairline.width)
            button("arrow.down.right.and.arrow.up.left", label: "Show the whole world", enabled: canZoomOut, action: onFit)
        }
        .background(Theme.bg.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func button(_ icon: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
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

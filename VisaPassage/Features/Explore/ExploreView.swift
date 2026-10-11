import SwiftUI

/// The Explore tab: where your passports can take you, laid out like Home (an
/// inset grouped list on the grouped ground, one scroll, nothing pinned).
/// Top to bottom, as on the web phone explorer: the title with Ranking; the
/// map card, with your passports and the purpose dropdown on top of the map
/// and the tapped country's panel under it; the map key, whose rows filter;
/// the search field; the destination tables. Every list reads the same
/// `RequirementsStore` (travel) or `PurposeRoutesStore` (other purposes) as
/// the map.
struct ExploreView: View {
    @Environment(ExploreSelection.self) private var explore
    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog
    @Environment(PurposeRoutesStore.self) private var routes

    @State private var path = NavigationPath()
    @State private var showPassports = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let searchID = "explore.search"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    Section {
                        TabHeader(title: Text("Explore")) {
                            HeaderButton("Ranking") { path.append(PassportRoute.ranking) }
                                .accessibilityLabel(Text("Passport ranking"))
                                .accessibilityIdentifier("explore.ranking")
                        }
                        .tabHeaderRow()
                    }
                    mapSection
                    if explore.purpose.isRoute {
                        routeSections
                    } else {
                        travelSections
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .scrollDismissesKeyboard(.immediately)
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { consumeFocusRequest(proxy) }
                .onChange(of: explore.focusSearch) { consumeFocusRequest(proxy) }
            }
            .catalogDestinations()
            .passportDestinations()
            .trackerDestinations()
            .passportsEditor(isPresented: $showPassports)
            .task { await passports.seedFromAccountIfEmpty() }
            .task(id: passports.passports) { await requirements.load(passports.passports) }
            .task(id: RouteLoadKey(purpose: explore.purpose, passports: passports.passports)) {
                await routes.load(purpose: explore.purpose, passports: passports.passports)
            }
            .task { openDebugRoute() }
            .onAppear(perform: consumePendingDetail)
            .onChange(of: explore.pendingDetail) { consumePendingDetail() }
            .onChange(of: explore.pendingRoute) { consumePendingRoute() }
            .onAppear { consumePendingRoute() }
            .onChange(of: explore.pendingPassport) { consumePendingPassport() }
            .onAppear { consumePendingPassport() }
        }
    }

    private var routeModel: RouteMapModel? {
        guard explore.purpose.isRoute, let current = routes.current else { return nil }
        return RouteMapModel(routes: current, home: Set(passports.passports), typeFilter: explore.typeFilter)
    }

    // MARK: - Map card

    /// One card: the pill (passports · purpose) on top, the map frame, and the
    /// tapped country's panel as the next row (web `PHONE_EXPLORE`).
    @ViewBuilder
    private var mapSection: some View {
        Section {
            VStack(spacing: Spacing.md) {
                MapToolbar(purpose: Binding(get: { explore.purpose }, set: { explore.purpose = $0 })) {
                    showPassports = true
                }
                map
                    .modifier(MapFrame())
            }
            .padding(Spacing.md)
            .listRowInsets(EdgeInsets())
            if let iso = explore.focusedDestination {
                panel(iso)
            }
        }
    }

    @ViewBuilder
    private var map: some View {
        let select: (String?) -> Void = { iso in
            withAnimation(.snappy(duration: 0.25)) { explore.focusedDestination = iso }
        }
        if explore.purpose.isRoute {
            ZStack {
                WorldMapView(
                    focused: explore.focusedDestination,
                    routeFills: routeModel?.fills(purpose: explore.purpose) ?? [:],
                    focusColor: RoutePalette.accent(explore.purpose),
                    interactive: true,
                    onTap: select
                )
                if routeModel == nil && !routes.failed { loadingBadge }
            }
        } else {
            ZStack {
                WorldMapView(filter: explore.filter, focused: explore.focusedDestination, interactive: true, onTap: select)
                if requirements.loading && requirements.best.isEmpty { loadingBadge }
            }
        }
    }

    private var loadingBadge: some View {
        ProgressView()
            .padding(Spacing.md)
            .background(Theme.bg, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func panel(_ iso: String) -> some View {
        let close = { withAnimation(.snappy(duration: 0.25)) { explore.focusedDestination = nil } }
        if explore.purpose.isRoute {
            if let current = routes.current {
                RoutePanel(iso2: iso, purpose: explore.purpose, routes: current, ageBand: explore.ageBand) {
                    pushRoute(iso)
                } onClose: { close() }
            }
        } else {
            DestinationPanel(iso2: iso) { push(iso) } onClose: { close() }
        }
    }

    // MARK: - Travel

    @ViewBuilder
    private var travelSections: some View {
        if passports.passports.isEmpty {
            Section { emptyState }
        } else {
            let excluding = Set(passports.passports)
            let loading = requirements.best.isEmpty && !requirements.failed
            Section {
                MapKeyCard(mode: .travel(
                    counts: loading ? nil : DestinationGrouping.counts(countries: catalog.countries, best: requirements.best, excluding: excluding),
                    active: explore.filter,
                    onToggle: { explore.filter = $0 }
                ))
                .listRowInsets(EdgeInsets())
            }
            searchSection
            if requirements.failed && requirements.best.isEmpty {
                Section {
                    retryRow(title: "Couldn't load destinations", message: "Check your connection and try again.") {
                        await requirements.load(passports.passports)
                    }
                }
            } else if loading {
                Section { loadingRow("Loading destinations…") }
            } else {
                let groups = DestinationGrouping.groups(
                    countries: catalog.countries,
                    best: requirements.best,
                    filter: explore.filter,
                    query: query,
                    excluding: excluding
                )
                if groups.isEmpty {
                    Section {
                        Text(query.isEmpty ? "No destinations match this filter." : "No destinations match your search.")
                            .typography(.sm)
                            .foregroundStyle(Theme.textBody)
                    }
                }
                DestinationSections(
                    groups: groups,
                    unlimited: !query.trimmingCharacters(in: .whitespaces).isEmpty || explore.filter != .all,
                    onSelect: push
                )
            }
        }
    }

    // MARK: - Route purposes

    @ViewBuilder
    private var routeSections: some View {
        @Bindable var explore = explore
        if let model = routeModel {
            let depth = model.depth(countries: catalog.countries)
            Section {
                MapKeyCard(
                    mode: .route(purpose: explore.purpose, buckets: depth.buckets, none: depth.none),
                    showHome: !passports.passports.isEmpty
                ) {
                    RouteTypeChips(
                        types: routes.current?.types ?? [],
                        counts: model.countsByType,
                        selection: $explore.typeFilter,
                        ageBand: $explore.ageBand
                    )
                }
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Unverified catalogue data. A route existing does not mean you qualify — eligibility depends on your passport, age and circumstances and requires review. Official decisions prevail.")
            }
            searchSection
            RouteSections(model: model, purpose: explore.purpose, query: query, onSelect: pushRoute)
        } else if routes.failed {
            Section {
                retryRow(title: "Could not load routes right now. Please try again in a moment.", message: nil) {
                    await routes.load(purpose: explore.purpose, passports: passports.passports)
                }
            }
        } else {
            Section { loadingRow("Loading routes…") }
        }
    }

    // MARK: - Shared rows

    private var searchSection: some View {
        Section {
            DestinationSearchField(query: $query, focused: $searchFocused)
                .id(Self.searchID)
        }
    }

    private func loadingRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
            Text(text).typography(.sm).foregroundStyle(Theme.textBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm)
    }

    private func retryRow(title: LocalizedStringKey, message: LocalizedStringKey?, retry: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(title, systemImage: "wifi.slash")
                .font(.custom("Geist-Medium", size: 15))
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message).typography(.sm).foregroundStyle(Theme.textBody)
            }
            Button("Try again") { Task { await retry() } }
                .buttonStyle(.borderless)
                .font(.custom("Geist-Medium", size: 15))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, Spacing.sm)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Add a passport to begin")
                .typography(.h3)
                .foregroundStyle(Theme.ink)
            Text("Pick the passport you travel on to see where you can go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { showPassports = true } label: {
                Text("Choose passport")
                    .typography(.sm)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 40)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Spacing.sm)
    }

    /// Home's "Where to?": scroll to the search field and focus it.
    private func consumeFocusRequest(_ proxy: ScrollViewProxy) {
        guard explore.focusSearch else { return }
        explore.focusSearch = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation { proxy.scrollTo(Self.searchID, anchor: .top) }
            searchFocused = true
        }
    }

    /// `pairHref`: with one passport, its corridor (routes by purpose for that
    /// pair); otherwise the destination guide.
    private func pushRoute(_ iso: String) {
        let destination = iso.uppercased()
        let held = passports.passports
        if held.count == 1, let passport = held.first, passport != destination {
            path.append(CatalogRoute.corridor(from: passport, to: destination))
        } else {
            path.append(CatalogRoute.destination(destination))
        }
    }

    // MARK: - Navigation

    /// The corridor for the passport that gets the best status there (the one
    /// the map shows), else the destination page.
    private func push(_ iso: String) {
        let destination = iso.uppercased()
        if let passport = bestPassport(for: destination) {
            path.append(CatalogRoute.corridor(from: passport, to: destination))
        } else {
            path.append(CatalogRoute.destination(destination))
        }
    }

    private func bestPassport(for destination: String) -> String? {
        let held = passports.passports.filter { $0 != destination }
        guard let best = requirements.row(for: destination) else { return held.first }
        return held.first { passport in
            requirements.rowsByPassport[passport]?.contains {
                $0.destinationIso2.uppercased() == destination && $0.status == best.status
            } ?? false
        } ?? held.first
    }

    /// Screenshots: `-debug.corridor UA-DE` opens that corridor, `-debug.destination DE` the destination,
    /// `-debug.passport UA` a passport page, `-debug.compare DE,UA` the compare, `-debug.ranking YES` the ranking.
    private func openDebugRoute() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let pair = defaults.string(forKey: "debug.corridor")?.split(separator: "-"), pair.count == 2 {
            path.append(CatalogRoute.corridor(from: String(pair[0]), to: String(pair[1])))
        } else if let iso = defaults.string(forKey: "debug.destination") {
            path.append(CatalogRoute.destination(iso))
        } else if let iso = defaults.string(forKey: "debug.passport") {
            path.append(PassportRoute.detail(iso))
        } else if let codes = defaults.string(forKey: "debug.compare") {
            path.append(PassportRoute.compare(codes.components(separatedBy: ",")))
        } else if defaults.bool(forKey: "debug.ranking") {
            path.append(PassportRoute.ranking)
        }
        #endif
    }

    private func consumePendingRoute() {
        guard let route = explore.pendingRoute else { return }
        explore.pendingRoute = nil
        path.append(route)
    }

    private func consumePendingPassport() {
        guard let iso = explore.pendingPassport else { return }
        explore.pendingPassport = nil
        path.append(PassportRoute.detail(iso))
    }

    private func consumePendingDetail() {
        guard let iso = explore.pendingDetail else { return }
        explore.pendingDetail = nil
        push(iso)
    }
}

/// The map frame inside the card: landscape (web `PHONE_MAP_H`, 0.72 of its
/// width; the map covers it and zooms), hairline, its own ocean.
private struct MapFrame: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        content
            .aspectRatio(1 / 0.72, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: Hairline.width))
    }
}

/// Reload routes whenever the purpose or the passports change.
private struct RouteLoadKey: Hashable {
    let purpose: Purpose
    let passports: [String]
}

// MARK: - Map toolbar

/// The pill on top of the map (web `StepBar floating`): your passports as a
/// flag stack, opening the editor, then the purpose dropdown.
private struct MapToolbar: View {
    @Binding var purpose: Purpose
    let onEditPassports: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onEditPassports) { passportsLabel }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Edit passports"))
                .accessibilityIdentifier("explore.passports")
            Rectangle()
                .fill(Theme.border)
                .frame(width: Hairline.width, height: 20)
            PurposeMenu(selection: $purpose)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .frame(height: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
    }

    @ViewBuilder
    private var passportsLabel: some View {
        let held = passports.passports
        HStack(spacing: Spacing.sm) {
            if held.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add passport").typography(.sm).lineLimit(1)
            } else {
                HStack(spacing: -8) {
                    ForEach(held.prefix(3), id: \.self) { iso in
                        CountryFlag(iso2: iso, size: 24)
                            .padding(1.5)
                            .background(Theme.surface, in: Circle())
                    }
                }
                if held.count == 1, let iso = held.first {
                    Text(catalog.name(forISO2: iso) ?? iso)
                        .typography(.sm)
                        .lineLimit(1)
                } else if held.count > 3 {
                    Text(verbatim: "+\(held.count - 3)")
                        .font(.custom("GeistMono-Regular", size: 12))
                        .foregroundStyle(Theme.textSoft)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.md)
        .frame(height: 36)
        .contentShape(Capsule())
    }
}

// MARK: - Destination panel

/// The tapped country's status for your passports: a row of the map card,
/// under the map.
private struct DestinationPanel: View {
    let iso2: String
    let onDetails: () -> Void
    let onClose: () -> Void

    @Environment(RequirementsStore.self) private var requirements
    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        let row = requirements.row(for: iso2)
        let status = row?.status ?? .unknown
        let isHome = passports.contains(iso2)
        let hue = status.hue
        RouteTicket(
            origin: isHome ? nil : passports.primary,
            destination: iso2,
            verdict: isHome ? String(localized: "Your passport") : status.label,
            detail: isHome ? nil : row?.daysAllowed.flatMap { $0 > 0 ? String(localized: "Up to \($0) days") : nil },
            tint: isHome ? MapPalette.home : (status == .unknown ? Theme.inkMuted : hue.softFg),
            tintBg: isHome ? MapPalette.home.opacity(0.1) : (status == .unknown ? Theme.surface2 : hue.softBg),
            glyph: { AnyView(StatusKeyIcon(glyph: isHome ? .home : .status(status), size: 14)) },
            onClose: onClose
        ) {
            if !isHome {
                Button(action: onDetails) {
                    HStack(spacing: Spacing.sm) {
                        Text("See details").typography(.sm)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressShrinkStyle())
                .accessibilityLabel(Text("See details"))
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

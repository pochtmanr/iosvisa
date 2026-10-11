import SwiftUI

/// The Explore tab: where your passports can take you. A passport bar, Map or
/// List, and the status filter chips. Map and List share one
/// `RequirementsStore`, so they always show the same data. Tapping a country
/// on the map opens a bottom panel; "See details" pushes the corridor.
struct ExploreView: View {
    @Environment(ExploreSelection.self) private var explore
    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog

    @State private var path = NavigationPath()
    @State private var showPassports = false

    var body: some View {
        @Bindable var explore = explore
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                PassportBar { showPassports = true }
                if !passports.passports.isEmpty {
                    Picker("View", selection: $explore.mode) {
                        Text("Map").tag(ExploreSelection.Mode.map)
                        Text("List").tag(ExploreSelection.Mode.list)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.sm)
                    FilterChips(selection: $explore.filter)
                }
                Divider().overlay(Theme.border)
                content
            }
            .background(Theme.bg)
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .catalogDestinations()
            .sheet(isPresented: $showPassports) {
                PassportsSheet()
            }
            .task { await passports.seedFromAccountIfEmpty() }
            .task(id: passports.passports) { await requirements.load(passports.passports) }
            .task { openDebugRoute() }
            .onAppear(perform: consumePendingDetail)
            .onChange(of: explore.pendingDetail) { consumePendingDetail() }
            .onChange(of: explore.pendingRoute) { consumePendingRoute() }
            .onAppear { consumePendingRoute() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var content: some View {
        if passports.passports.isEmpty {
            emptyState
        } else if requirements.failed && requirements.best.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load destinations", systemImage: "wifi.slash")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try again") { Task { await requirements.load(passports.passports) } }
            }
        } else {
            switch explore.mode {
            case .map:
                mapMode
            case .list:
                DestinationListView(onSelect: push)
            }
        }
    }

    private var mapMode: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                WorldMapView(filter: explore.filter, focused: explore.focusedDestination) { iso in
                    withAnimation(.snappy(duration: 0.25)) { explore.focusedDestination = iso }
                }
                if requirements.loading && requirements.best.isEmpty {
                    ProgressView()
                        .padding(Spacing.md)
                        .background(Theme.bg, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let iso = explore.focusedDestination {
                    DestinationPanel(iso2: iso) {
                        push(iso)
                    } onClose: {
                        withAnimation(.snappy(duration: 0.25)) { explore.focusedDestination = nil }
                    }
                    .padding(Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Divider().overlay(Theme.border)
            MapLegend()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "globe")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkSoft)
            Text("Add a passport to begin").typography(.h3)
            Text("Pick the passport you travel on to see where you can go.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
            Button("Choose passport") { showPassports = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Screenshots: `-debug.corridor UA-DE` opens that corridor, `-debug.destination DE` the destination.
    private func openDebugRoute() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let pair = defaults.string(forKey: "debug.corridor")?.split(separator: "-"), pair.count == 2 {
            path.append(CatalogRoute.corridor(from: String(pair[0]), to: String(pair[1])))
        } else if let iso = defaults.string(forKey: "debug.destination") {
            path.append(CatalogRoute.destination(iso))
        }
        #endif
    }

    private func consumePendingRoute() {
        guard let route = explore.pendingRoute else { return }
        explore.pendingRoute = nil
        path.append(route)
    }

    private func consumePendingDetail() {
        guard let iso = explore.pendingDetail else { return }
        explore.pendingDetail = nil
        push(iso)
    }
}

// MARK: - Passport bar

/// The selected passports as chips (primary first), plus an edit button.
private struct PassportBar: View {
    let onEdit: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Eyebrow(text: "Passports")
            ForEach(passports.passports, id: \.self) { iso in
                HStack(spacing: Spacing.xs) {
                    CountryFlag(iso2: iso, size: 18)
                    Text(catalog.name(forISO2: iso) ?? iso)
                        .typography(.sm)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
            }
            Spacer(minLength: 0)
            Button(action: onEdit) {
                Image(systemName: passports.passports.isEmpty ? "plus" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: Hairline.width))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit passports"))
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Filter chips

/// All · Visa-free · Visa on arrival · eVisa · Visa required, each with its map colour.
struct FilterChips: View {
    @Binding var selection: ExploreFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(ExploreFilter.allCases) { filter in
                    let selected = filter == selection
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = filter }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if let status = filter.swatch {
                                MapSwatch(fill: status.mapFill)
                            }
                            Text(filter.title).typography(.sm).fixedSize()
                        }
                        .foregroundStyle(selected ? Theme.inkInverse : Theme.ink)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.ink : Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? .clear : Theme.border, lineWidth: Hairline.width))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.md)
        }
    }
}

// MARK: - Bottom panel

/// The tapped country's status for your passports, over the bottom of the map.
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                CountryFlag(iso2: iso2, size: 32)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(catalog.name(forISO2: iso2) ?? iso2)
                        .typography(.title)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: Spacing.sm) {
                        if isHome {
                            Text("Your passport").typography(.sm).foregroundStyle(Theme.textBody)
                        } else if status == .unknown {
                            Text(status.label).typography(.sm).foregroundStyle(Theme.textSoft)
                        } else {
                            StatusBadge(text: status.label, hue: status.hue)
                            if let days = row?.daysAllowed, days > 0 {
                                Text("Up to \(days) days").typography(.xs).foregroundStyle(Theme.textBody)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
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
            }
        }
        .padding(Spacing.lg)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

import SwiftUI

// Explore for the non-travel purposes, ported from the landing checker
// (`useCheckerState`, `MapKey` route mode, `DestinationPanel` route groups and
// `RouteDetail` in `web/src/app/[locale]/visa-checker/_components/RoutePanels.tsx`).

/// Age bands (`AGE_BANDS`): they line up with the thresholds routes use.
enum AgeBand: String, CaseIterable, Identifiable, Sendable {
    case u18, from18to30 = "18_30", from31to35 = "31_35", from36to50 = "36_50", plus51 = "51_plus"
    var id: Self { self }

    var label: String {
        switch self {
        case .u18: return String(localized: "Under 18")
        case .from18to30: return "18–30"
        case .from31to35: return "31–35"
        case .from36to50: return "36–50"
        case .plus51: return "51+"
        }
    }

    /// Bands where a working-holiday route's age cap is likely to bite.
    var outsideWorkingHoliday: Bool { [.u18, .from36to50, .plus51].contains(self) }
}

/// The pure route-map model for one response, the passports you hold and the
/// type chip: the same derived sets the web hook builds.
struct RouteMapModel {
    let routes: CheckerRoutes
    let home: Set<String>
    let typeFilter: String?

    /// Destination → every route it has for this purpose (no filter).
    var allRoutes: [String: [CheckerRoute]] {
        routes.destinations.filter { !$0.value.isEmpty }
    }

    /// Destination → routes narrowed by the visa-type chip.
    var filteredRoutes: [String: [CheckerRoute]] {
        guard let typeFilter else { return allRoutes }
        var out: [String: [CheckerRoute]] = [:]
        for (iso, list) in allRoutes {
            let kept = list.filter { $0.visaTypeCode == typeFilter }
            if !kept.isEmpty { out[iso] = kept }
        }
        return out
    }

    /// Distinct visa types a list covers (the depth on the map).
    static func kinds(_ list: [CheckerRoute]) -> Int {
        Set(list.map(\.visaTypeCode)).count
    }

    /// Map fills: depth from every route (`routeFillByNumeric`); countries the
    /// chip hides get the muted ground instead (`routeMutedNumerics`).
    func fills(purpose: Purpose) -> [String: Color] {
        let shown = filteredRoutes
        var out: [String: Color] = [:]
        for (iso, list) in allRoutes {
            if typeFilter != nil && shown[iso] == nil {
                out[iso] = RoutePalette.empty
            } else {
                out[iso] = RoutePalette.fill(typeCount: Self.kinds(list), purpose: purpose)
            }
        }
        return out
    }

    /// Destinations per visa type (`routeCountsByType`).
    var countsByType: [String: Int] {
        var counts: [String: Int] = [:]
        for list in routes.destinations.values {
            for code in Set(list.map(\.visaTypeCode)) { counts[code, default: 0] += 1 }
        }
        return counts
    }

    /// The map key's buckets: 1, 2, 3+ types, and no route, over `countries`
    /// without your own passports' countries.
    func depth(countries: [Country]) -> (buckets: [Int], none: Int) {
        var buckets = [0, 0, 0]
        var withRoutes = 0
        for (iso, list) in filteredRoutes where !home.contains(iso) {
            withRoutes += 1
            buckets[min(Self.kinds(list), 3) - 1] += 1
        }
        let total = countries.filter { !home.contains($0.iso2.uppercased()) }.count
        return (buckets, total - withRoutes)
    }

    struct Row: Identifiable {
        let country: Country
        let routeCount: Int
        var id: String { country.iso2 }
    }

    /// The list: "With a route" (most routes first, then by name) and "No route"
    /// (by name). Countries the chip hides leave the list; they still have routes.
    func groups(countries: [Country], query: String) -> (routes: [Row], none: [Row]) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let shown = filteredRoutes
        let all = allRoutes
        var with: [Row] = []
        var without: [Row] = []
        for c in countries {
            let iso = c.iso2.uppercased()
            guard !home.contains(iso) else { continue }
            if !needle.isEmpty,
               !c.displayName.localizedCaseInsensitiveContains(needle),
               iso.caseInsensitiveCompare(needle) != .orderedSame {
                continue
            }
            if let list = shown[iso], !list.isEmpty {
                with.append(Row(country: c, routeCount: list.count))
            } else if all[iso] == nil {
                without.append(Row(country: c, routeCount: 0))
            }
        }
        with.sort {
            $0.routeCount != $1.routeCount
                ? $0.routeCount > $1.routeCount
                : $0.country.displayName.localizedStandardCompare($1.country.displayName) == .orderedAscending
        }
        without.sort { $0.country.displayName.localizedStandardCompare($1.country.displayName) == .orderedAscending }
        return (with, without)
    }
}

// MARK: - Purpose menu

// PurposeMenu: ExploreTicket.swift (custom dropdown with icons).

// MARK: - Type chips and age

/// The age menu and the visa-type chips at the foot of the route map key
/// (`MapKey` route mode), each chip with how many destinations publish it.
/// Chips show when the purpose has more than one type. They wrap.
struct RouteTypeChips: View {
    let types: [CheckerRoutes.VisaType]
    let counts: [String: Int]
    @Binding var selection: String?
    @Binding var ageBand: AgeBand?

    var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            AgeMenu(selection: $ageBand)
            if types.count > 1 {
                ForEach(types) { type in
                    let active = selection == type.code
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = active ? nil : type.code }
                    } label: {
                        HStack(spacing: 6) {
                            Text(type.name).typography(.sm).fixedSize()
                            Text(verbatim: "\(counts[type.code] ?? 0)")
                                .font(Typography.font(.monoSm))
                                .opacity(0.7)
                        }
                        .foregroundStyle(active ? Theme.inkInverse : Theme.ink)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(active ? Theme.ink : Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? .clear : Theme.border, lineWidth: Hairline.width))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter by visa type"))
    }
}

/// "Your age": optional, it only refines the working-holiday note.
private struct AgeMenu: View {
    @Binding var selection: AgeBand?

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                Text("Any age").tag(AgeBand?.none)
                ForEach(AgeBand.allCases) { band in
                    Text(band.label).tag(AgeBand?.some(band))
                }
            } label: {
                Text("Your age")
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(selection?.label ?? String(localized: "Your age")).typography(.sm).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
    }
}

// MARK: - Destination panel

/// The tapped country's routes for the purpose (`RouteDetail`): a header with
/// the route count and Unverified, up to six routes (type chip in the purpose
/// hue, eligibility, rights, stay and processing), then "See routes & documents".
/// A row of the map card, under the map.
struct RoutePanel: View {
    let iso2: String
    let purpose: Purpose
    let routes: CheckerRoutes
    let ageBand: AgeBand?
    let onDetails: () -> Void
    let onClose: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    private static let shownRoutes = 6

    var body: some View {
        let list = routes.destinations[iso2.uppercased()] ?? []
        let isHome = passports.contains(iso2)
        let accent = RoutePalette.accent(purpose)
        RouteTicket(
            origin: isHome ? nil : passports.primary,
            destination: iso2,
            verdict: isHome
                ? String(localized: "Your passport")
                : (list.isEmpty ? String(localized: "No route in our catalogue") : String(localized: "\(list.count) routes")),
            detail: String(localized: "Unverified"),
            tint: accent,
            tintBg: accent.opacity(0.1),
            glyph: { AnyView(PurposeIcon(purpose: purpose, size: 15)) },
            onClose: onClose
        ) {
          VStack(alignment: .leading, spacing: Spacing.md) {
            if isHome {
                Text("This is your passport's home country — you don't need a visa to live, study or work here.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            } else if list.isEmpty {
                Text("We have no route of this kind for this destination yet. That does not mean none exists — check the destination guide.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.prefix(Self.shownRoutes).enumerated()), id: \.element.id) { index, route in
                        if index > 0 { Divider().overlay(Theme.border) }
                        Button(action: onDetails) { RouteRow(route: route, purpose: purpose, routes: routes, ageBand: ageBand) }
                            .buttonStyle(.plain)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: Hairline.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                if list.count > Self.shownRoutes {
                    Text("\(list.count - Self.shownRoutes) more routes in the guide.")
                        .typography(.xs)
                        .foregroundStyle(Theme.textSoft)
                }
            }
            if !isHome {
                Divider().overlay(Theme.border)
                Button(action: onDetails) {
                    HStack(spacing: Spacing.sm) {
                        Text("See routes & documents").typography(.sm)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressShrinkStyle())
                Text(ageBand == nil
                     ? "Add your age to flag routes with age limits."
                     : "Age-specific eligibility is being added route by route.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            }
          }
        }
        .padding(.vertical, Spacing.sm)
    }
}

/// A neutral status pill (the web `StatusBadge tone="neutral"`).
struct NeutralBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .typeRole(.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Theme.surface2, in: Capsule())
    }
}

/// One route in the panel (`RouteDetail` row).
private struct RouteRow: View {
    let route: CheckerRoute
    let purpose: Purpose
    let routes: CheckerRoutes
    let ageBand: AgeBand?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(route.name)
                    .font(.custom("Geist-Medium", size: 14))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle().fill(RoutePalette.accent(purpose)).frame(width: 6, height: 6)
                        Text(routes.typeName(route.visaTypeCode))
                    }
                    .chip(background: RoutePalette.depth(1, purpose), foreground: Theme.ink)
                    eligibilityChip
                    ForEach(route.rights, id: \.key) { right in
                        Text(right.label)
                            .chip(background: Theme.bg, foreground: Theme.inkMuted, bordered: true)
                    }
                }
                if route.visaTypeCode == "working_holiday", ageBand?.outsideWorkingHoliday == true {
                    Text("Working-holiday programmes set age limits (often 18–30 or 18–35). Requires review.")
                        .typography(.xs)
                        .foregroundStyle(Theme.textBody)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let days = route.maxStayDays {
                    Text("\(days) d stay")
                }
                if let days = route.processingTimeDays {
                    Text("~\(days) d processing")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 2)
            }
            .font(.custom("GeistMono-Regular", size: 11.5))
            .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var eligibilityChip: some View {
        switch route.eligibility {
        case .eligible:
            Text(String(localized: "routes.chip.eligible", defaultValue: "May be eligible")).chip(background: StatusHue.green.softBg, foreground: StatusHue.green.softFg)
        case .conditional, .unknown:
            Text("Conditions apply").chip(background: StatusHue.yellow.softBg, foreground: StatusHue.yellow.softFg)
        case .notEligible:
            Text("Not open to you").chip(background: StatusHue.red.softBg, foreground: StatusHue.red.softFg)
        }
    }
}

private extension View {
    /// The web route chip: 22pt pill, 11.5pt medium.
    func chip(background: Color, foreground: Color, bordered: Bool = false) -> some View {
        self
            .font(.custom("Geist-Medium", size: 11.5))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 22)
            .background(background, in: Capsule())
            .overlay {
                if bordered { Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width) }
            }
    }
}

// MARK: - Tables

/// Route-mode tables: "With a route" by route count (limited, then "Show
/// all"), then "No route in our catalogue", folded until opened or searched.
/// Sections only: place it inside a `List`.
struct RouteSections: View {
    let model: RouteMapModel
    let purpose: Purpose
    let query: String
    let onSelect: (String) -> Void

    @Environment(CountryStore.self) private var catalog
    @State private var showAll = false
    @State private var showNone = false

    var body: some View {
        let groups = model.groups(countries: catalog.countries, query: query)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if model.allRoutes.isEmpty {
            Section {
                Text("Our catalogue has no routes for this purpose yet. That does not mean none exist — check the destination guides.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            }
        } else if groups.routes.isEmpty && groups.none.isEmpty {
            Section {
                Text(searching ? "No destinations match your search." : "No destinations match this filter.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            }
        }
        if !groups.routes.isEmpty {
            let open = searching || model.typeFilter != nil || showAll
            let shown = DestinationGrouping.visibleCount(total: groups.routes.count, expanded: open)
            Section {
                ForEach(groups.routes.prefix(shown)) { row in
                    Button { onSelect(row.country.iso2) } label: { RouteListRow(row: row) }
                        .foregroundStyle(Theme.ink)
                }
                if !searching && model.typeFilter == nil && groups.routes.count > DestinationGrouping.rowLimit {
                    ShowAllRow(expanded: showAll, hidden: groups.routes.count - shown) { showAll.toggle() }
                }
            } header: {
                StatusSectionHeader(count: groups.routes.count) {
                    PurposeIcon(purpose: purpose, size: 16)
                        .foregroundStyle(RoutePalette.accent(purpose))
                } title: {
                    Text("With a route")
                }
            }
        }
        if !groups.none.isEmpty && !model.allRoutes.isEmpty {
            Section {
                if showNone || searching {
                    ForEach(groups.none) { row in
                        Button { onSelect(row.country.iso2) } label: { RouteListRow(row: row) }
                            .foregroundStyle(Theme.ink)
                    }
                }
                if !searching {
                    ShowAllRow(expanded: showNone, hidden: groups.none.count) { showNone.toggle() }
                }
            } header: {
                StatusSectionHeader(count: groups.none.count) {
                    MapSwatch(fill: RoutePalette.empty, size: 14)
                } title: {
                    Text("No route in our catalogue")
                }
            }
        }
    }
}

private struct RouteListRow: View {
    let row: RouteMapModel.Row

    var body: some View {
        HStack(spacing: Spacing.md) {
            CountryFlag(iso2: row.country.iso2, size: 24)
            Text(row.country.displayName)
                .typography(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.routeCount > 0 {
                Text("\(row.routeCount) routes")
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSoft)
        }
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// Screen 15, `/passports/[slug]` (web profile page + drawer): the hero with
/// the hairline stat grid and status bar, where the passport takes you (status
/// list + map), the longest visa-free stays, the best second passports, and
/// every destination by status. Rank and counts come from the shared ranking
/// (`DenseRank`); destinations come from the cached `visa_requirements` slice,
/// so the page also works offline. Second passports come from the web's
/// summary route and simply hide when it can't be reached.
struct PassportDetailView: View {
    let iso2: String

    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(PassportPreference.self) private var passports
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var model = PassportDetailModel()
    @State private var explained: VisaStatus?
    @State private var showAllStays = false
    @State private var filter = DestinationFilter()
    @State private var width: CGFloat = 0

    init(iso2: String) {
        self.iso2 = iso2.uppercased()
    }

    private var wide: Bool { sizeClass == .regular || width >= 720 }
    private var gutter: CGFloat { wide ? Spacing.xxl : Spacing.lg }

    var body: some View {
        let index = strength.index(countries: catalog.countries)
        let row = index.first { $0.iso2 == iso2 }
        let name = catalog.name(forISO2: iso2) ?? iso2
        let slug = catalog.country(iso2)?.slug
        let url = AppLocale.current.passportURL(slug: slug)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        hero(name: name, row: row, total: index.count)
                        reach(name: name, row: row) { status in
                            filter.status = nil
                            withAnimation(.snappy) { proxy.scrollTo(DestinationFilter.anchor(status), anchor: .top) }
                        }
                        stays
                        combos(name: name)
                    }
                    .padding(.horizontal, gutter)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                    .readableWidth()

                    destinations
                }
            }
        }
        .background(Theme.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let row {
                ToolbarItem(placement: .topBarTrailing) {
                    let rank = PassportRank(row, totalRanked: index.count)
                    ShareCardButton(url: url, renderID: "\(iso2)-\(rank.rank)") {
                        PassportRankShareCard(iso2: iso2, name: name, rank: rank, url: url)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .statusExplainer($explained)
        .task { await strength.loadIfNeeded() }
        .task(id: iso2) { await model.load(iso2, countries: catalog.countries) }
        .task(id: slug) {
            if let slug { await model.loadSummary(slug: slug) }
        }
        .onChange(of: catalog.countries.count) { model.rename(catalog.countries) }
        .onChange(of: row?.rank, initial: true) { _, rank in
            guard let rank else { return }
            SpotlightIndexer.indexPassport(iso2, name: name, rank: rank, url: url)
        }
    }

    // MARK: - Hero

    private func hero(name: String, row: PassportIndexRow?, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                CountryFlag(iso2: iso2, size: wide ? 64 : 52)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: passports.contains(iso2) ? "Your passport" : "Passport Power Index")
                    Text(verbatim: name)
                        .typography(wide ? .display : .h1)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if row == nil, strength.loadFailed {
                CatalogStateCard(kind: .failed) { Task { await strength.reload() } }
            } else if row == nil, !strength.index(countries: catalog.countries).isEmpty {
                CatalogStateCard(kind: .empty, message: String(localized: "This passport isn't in the ranking yet."))
            } else {
                let r = row ?? .placeholder
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HairlineStatGrid(items: [
                        .init(label: "Rank", value: "#\(r.rank)", sub: String(localized: "of \(total)")),
                        .init(label: "Mobility score", value: "\(r.mobilityScore)",
                              sub: String(localized: "of \(r.known) destinations")),
                        .init(label: "Visa-free", value: "\(r.counts.visaFree)", sub: String(localized: "no visa needed")),
                        .init(label: "Visa on arrival", value: "\(r.counts.visaOnArrival)",
                              sub: String(localized: "issued at the border")),
                    ], columns: wide ? 4 : 2)
                    PassportStatusBar(counts: r.counts, size: .lg)
                    StatusLegend(counts: r.counts) { explained = $0 }
                }
                .redacted(reason: row == nil ? .placeholder : [])
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) { actions(fill: false) }
                VStack(spacing: Spacing.sm) { actions(fill: true) }
            }
        }
    }

    @ViewBuilder
    private func actions(fill: Bool) -> some View {
        let others = passports.passports.filter { $0 != iso2 }
        NavigationLink(value: PassportRoute.compare([iso2] + others.prefix(1))) {
            HStack(spacing: Spacing.sm) {
                Text("Compare with another passport").typography(.sm)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.inkInverse)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 44)
            .background(Theme.ink, in: Capsule())
        }
        .buttonStyle(PressShrinkStyle())
        .accessibilityIdentifier("passport.compare")
        NavigationLink(value: PassportRoute.ranking) {
            Text("All passports")
                .typography(.sm)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Spacing.lg)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: 44)
                .background(Theme.surface2, in: Capsule())
        }
        .buttonStyle(PressShrinkStyle())
    }

    // MARK: - Where it takes you

    private func reach(name: String, row: PassportIndexRow?, jump: @escaping (VisaStatus) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            PassportSectionTitle(
                title: String(localized: "Where the \(name) passport takes you"),
                lede: String(localized: "The mobility score counts visa-free and visa-on-arrival destinations only. eVisa and eTA access is listed separately. Figures describe typical eligibility, never a promise of admission.")
            )
            if wide {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    statusList(row, jump: jump).frame(width: 320)
                    map
                }
            } else {
                map
                statusList(row, jump: jump)
            }
        }
    }

    @ViewBuilder
    private func statusList(_ row: PassportIndexRow?, jump: @escaping (VisaStatus) -> Void) -> some View {
        if let row {
            let present = PassportCounts.statuses.filter { row.counts[$0] > 0 }
            VStack(spacing: 0) {
                ForEach(Array(present.enumerated()), id: \.element) { i, status in
                    if i > 0 { RowDivider(inset: 0) }
                    Button { jump(status) } label: {
                        HStack(spacing: Spacing.md) {
                            StatusKeyIcon(status, size: 20)
                            Text(verbatim: status.shortLabel)
                                .typography(.sm)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: Spacing.sm)
                            Text(verbatim: percent(row.counts[status], of: row.known))
                                .font(Typography.font(.monoSm))
                                .foregroundStyle(Theme.textSoft)
                            Text(verbatim: "\(row.counts[status])")
                                .font(Typography.font(.monoBody))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                                .frame(minWidth: 34, alignment: .trailing)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(status.shortLabel), \(row.counts[status])"))
                }
            }
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
    }

    private func percent(_ n: Int, of total: Int) -> String {
        guard total > 0 else { return "" }
        return (Double(n) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
    }

    private var map: some View {
        WorldMapView(statuses: model.statuses, home: [iso2], onTap: { _ in })
            .aspectRatio(916 / 470, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .overlay {
                if model.loading && model.statuses.isEmpty { ProgressView() }
            }
            .padding(Spacing.sm)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Access by entry status"))
    }

    // MARK: - Longest stays

    @ViewBuilder
    private var stays: some View {
        let all = model.topVisaFree
        let visible = showAllStays ? all : Array(all.prefix(12))
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PassportSectionTitle(title: String(localized: "Longest visa-free stays"))
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(visible) { stay in
                        NavigationLink(value: CatalogRoute.corridor(from: iso2, to: stay.iso2)) {
                            HStack(spacing: 6) {
                                CountryFlag(iso2: stay.iso2, size: 16)
                                Text(verbatim: stay.name)
                                    .typography(.xs)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                if let days = stay.daysAllowed {
                                    Text("\(days) days")
                                        .font(Typography.font(.monoSm))
                                        .foregroundStyle(Theme.textSoft)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if all.count > visible.count {
                    showAll(all.count) { showAllStays = true }
                }
            }
        } else if model.failed {
            CatalogStateCard(kind: .failed) { Task { await model.load(iso2, countries: catalog.countries, force: true) } }
        }
    }

    // MARK: - Second passports

    @ViewBuilder
    private func combos(name: String) -> some View {
        if let combos = model.summary?.combos, !combos.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PassportSectionTitle(
                    title: String(localized: "Best second passports"),
                    lede: String(localized: "Passports that add the most new visa-free and visa-on-arrival destinations on top of the \(name) passport.")
                )
                VStack(spacing: 0) {
                    ForEach(Array(combos.enumerated()), id: \.element.id) { i, combo in
                        if i > 0 { RowDivider(inset: 0) }
                        NavigationLink(value: PassportRoute.compare([iso2, combo.iso2])) {
                            HStack(spacing: Spacing.md) {
                                CountryFlag(iso2: combo.iso2, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: catalog.name(forISO2: combo.iso2) ?? combo.name)
                                        .typography(.sm)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Text("combined \(combo.combinedMobility)")
                                        .typography(.xs)
                                        .foregroundStyle(Theme.textSoft)
                                }
                                Spacer(minLength: Spacing.sm)
                                Text(verbatim: "+\(combo.uplift)")
                                    .font(Typography.font(.monoBody))
                                    .foregroundStyle(Theme.ink)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, Spacing.lg)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width))
            }
        }
    }

    // MARK: - Every destination

    @ViewBuilder
    private var destinations: some View {
        let all = model.destinations
        if !all.isEmpty {
            let regions = PassportFilters.regions.filter { r in all.contains { $0.region == r } }
            let matching = filter.apply(all)
            Section {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if matching.isEmpty {
                        Text("No destination matches “\(filter.query)”.")
                            .typography(.sm)
                            .foregroundStyle(Theme.textBody)
                            .padding(.vertical, Spacing.xl)
                    }
                    ForEach(PassportCounts.statuses, id: \.self) { status in
                        let group = matching.filter { $0.status == status }
                        if !group.isEmpty, filter.status == nil || filter.status == status {
                            destinationGroup(status, group)
                                .id(DestinationFilter.anchor(status))
                        }
                    }
                    AdvisoryDisclaimer()
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, Spacing.xl)
                .readableWidth()
                .background(Theme.surface)
            } header: {
                destinationToolbar(all: all, matching: matching, regions: regions)
            }
        } else {
            AdvisoryDisclaimer()
                .padding(gutter)
                .readableWidth()
        }
    }

    private func destinationToolbar(all: [PassportDetailModel.Destination],
                                    matching: [PassportDetailModel.Destination],
                                    regions: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Every destination, by status")
                    .typography(.title)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.sm)
                Text("\(filter.visible(matching).count) destinations")
                    .font(Typography.font(.monoSm))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize()
            }
            HStack(spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                    TextField("Filter destinations, e.g. Brazil", text: $filter.query)
                        .typography(.sm)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !filter.query.isEmpty {
                        Button { filter.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear"))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Theme.bg, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))

                if regions.count > 1 {
                    Menu {
                        Picker("Filter by region", selection: $filter.region) {
                            Text("All regions").tag(String?.none)
                            ForEach(regions, id: \.self) { r in
                                Text(verbatim: PassportFilters.regionTitle(r)).tag(Optional(r))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: filter.region.map(PassportFilters.regionTitle) ?? String(localized: "All regions"))
                                .typography(.sm)
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(filter.region == nil ? Theme.textBody : Theme.inkInverse)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(filter.region == nil ? Theme.bg : Theme.ink, in: Capsule())
                        .overlay(Capsule().strokeBorder(filter.region == nil ? Theme.border : Theme.ink,
                                                        lineWidth: Hairline.width))
                    }
                    .fixedSize()
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    PillChip(title: String(localized: "All"), selected: filter.status == nil, count: matching.count) {
                        filter.status = nil
                    }
                    ForEach(PassportCounts.statuses, id: \.self) { status in
                        let n = matching.filter { $0.status == status }.count
                        if all.contains(where: { $0.status == status }) {
                            PillChip(title: status.shortLabel, selected: filter.status == status, count: n) {
                                filter.status = filter.status == status ? nil : status
                            } leading: {
                                StatusKeyIcon(status, size: 14)
                            }
                        }
                    }
                }
                .padding(.horizontal, gutter)
            }
            .padding(.horizontal, -gutter)
            .scrollClipDisabled()
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, Spacing.md)
        .readableWidth()
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
    }

    private func destinationGroup(_ status: VisaStatus, _ group: [PassportDetailModel.Destination]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                StatusKeyIcon(status, size: 20)
                Text(verbatim: status.shortLabel)
                    .typography(.bodyLg)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "\(group.count)")
                    .font(Typography.font(.monoSm))
                    .foregroundStyle(Theme.textSoft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Hairline.width),
                                     count: width >= 1000 ? 3 : (width >= 560 ? 2 : 1)),
                      spacing: Hairline.width) {
                ForEach(group) { d in
                    NavigationLink(value: CatalogRoute.corridor(from: iso2, to: d.iso2)) {
                        HStack(spacing: 10) {
                            CountryFlag(iso2: d.iso2, size: 20)
                            Text(verbatim: d.name)
                                .typography(.sm)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.sm)
                            if let days = d.daysAllowed {
                                Text("\(days) days")
                                    .font(Typography.font(.monoSm))
                                    .foregroundStyle(Theme.textSoft)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(Theme.bg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.border)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
    }

    private func showAll(_ count: Int, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text("Show all \(count)")
                .typography(.sm)
                .foregroundStyle(Theme.ink)
                .underline()
        }
        .buttonStyle(.plain)
    }
}

/// The destination explorer's filters (web `DestinationExplorer`).
struct DestinationFilter: Equatable {
    var query = ""
    var region: String?
    /// nil = "All".
    var status: VisaStatus?

    static func anchor(_ status: VisaStatus) -> String { "status-\(status.rawValue)" }

    /// Query and region (the status tabs count over this set).
    func apply(_ rows: [PassportDetailModel.Destination]) -> [PassportDetailModel.Destination] {
        let key = PassportFilters.searchKey(query)
        return rows.filter { d in
            (region == nil || d.region == region)
                && (key.isEmpty || PassportFilters.searchKey(d.name).contains(key) || d.iso2.lowercased() == key)
        }
    }

    /// What the page shows: `apply` narrowed to the selected status tab.
    func visible(_ matching: [PassportDetailModel.Destination]) -> [PassportDetailModel.Destination] {
        guard let status else { return matching }
        return matching.filter { $0.status == status }
    }
}

/// The passport page's destination data: its `visa_requirements` slice
/// (cached), folded into the map's statuses, the top visa-free stays and the
/// destination explorer; plus the web summary's second passports.
@MainActor
@Observable
final class PassportDetailModel {
    /// One destination in the explorer.
    struct Destination: Identifiable, Hashable, Sendable {
        var iso2: String
        var name: String
        var region: String?
        var status: VisaStatus
        var daysAllowed: Int?
        var id: String { iso2 }
    }

    private(set) var statuses: [String: VisaStatus] = [:]
    private(set) var topVisaFree: [PassportFilters.Stay] = []
    private(set) var destinations: [Destination] = []
    private(set) var summary: PassportSummary?
    private(set) var loading = false
    private(set) var failed = false

    private let repo: RequirementsRepository
    private let ranking: PassportRankingRepository
    private var loadedISO: String?
    private var rows: [VisaRequirement] = []
    private var countries: [String: Country] = [:]

    init(repo: RequirementsRepository = RequirementsRepository(),
         ranking: PassportRankingRepository = PassportRankingRepository()) {
        self.repo = repo
        self.ranking = ranking
    }

    func load(_ iso2: String, countries: [Country], force: Bool = false) async {
        guard force || loadedISO != iso2 else { return }
        setCountries(countries)
        loading = true
        failed = false
        defer { loading = false }
        do {
            let rows = try await repo.requirements(passport: iso2) { [weak self] fresh in
                await self?.apply(fresh)
            }
            apply(rows)
            loadedISO = iso2
        } catch {
            failed = true
        }
    }

    /// Optional extras; the section hides when this fails.
    func loadSummary(slug: String) async {
        summary = try? await ranking.summary(slug: slug) { [weak self] fresh in
            await self?.setSummary(fresh)
        }
    }

    private func setSummary(_ fresh: PassportSummary) {
        summary = fresh
    }

    /// Re-resolve names once the catalog arrives after the rows.
    func rename(_ countries: [Country]) {
        setCountries(countries)
        apply(rows)
    }

    private func setCountries(_ list: [Country]) {
        var byISO: [String: Country] = [:]
        for c in list { byISO[c.iso2.uppercased()] = c }
        countries = byISO
    }

    private func apply(_ rows: [VisaRequirement]) {
        self.rows = rows
        var statuses: [String: VisaStatus] = [:]
        var destinations: [Destination] = []
        for row in rows {
            let iso = row.destinationIso2.uppercased()
            statuses[iso] = row.status
            // The web drops destinations missing from `countries`.
            guard let country = countries[iso], row.status != .unknown else { continue }
            destinations.append(Destination(iso2: iso, name: country.displayName, region: country.region,
                                            status: row.status, daysAllowed: row.daysAllowed))
        }
        destinations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.statuses = statuses
        self.destinations = destinations
        let countries = countries
        topVisaFree = PassportFilters.topVisaFree(rows) { countries[$0]?.displayName }
    }
}

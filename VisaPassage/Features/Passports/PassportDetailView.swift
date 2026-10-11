import SwiftUI

/// Screen 15, `/passports/[slug]`: rank, mobility, the breakdown by status, a
/// small access map and the longest visa-free stays. Rank and counts come from
/// the shared ranking (`DenseRank`); the destinations come from the cached
/// `visa_requirements` slice, so the page also works offline.
struct PassportDetailView: View {
    let iso2: String

    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(PassportPreference.self) private var passports

    @State private var model = PassportDetailModel()
    @State private var showAllStays = false

    init(iso2: String) {
        self.iso2 = iso2.uppercased()
    }

    var body: some View {
        let index = strength.index(countries: catalog.countries)
        let row = index.first { $0.iso2 == iso2 }
        let name = catalog.name(forISO2: iso2) ?? iso2
        let url = AppLocale.current.passportURL(slug: catalog.country(iso2)?.slug)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header(name: name, row: row, total: index.count)
                if let row {
                    breakdown(row)
                } else if strength.loadFailed {
                    CatalogStateCard(kind: .failed) { Task { await strength.reload() } }
                } else if !index.isEmpty {
                    CatalogStateCard(kind: .empty, message: String(localized: "This passport isn't in the ranking yet."))
                }
                mapCard
                stays(name: name)
                compareLink
                AdvisoryDisclaimer()
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
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
        .task { await strength.loadIfNeeded() }
        .task(id: iso2) { await model.load(iso2, countries: catalog.countries) }
        .onChange(of: catalog.countries.count) { model.rename(catalog.countries) }
        .onChange(of: row?.rank, initial: true) { _, rank in
            guard let rank else { return }
            SpotlightIndexer.indexPassport(iso2, name: name, rank: rank, url: url)
        }
    }

    // MARK: - Sections

    private func header(name: String, row: PassportIndexRow?, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: iso2, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: passports.contains(iso2) ? "Your passport" : "Passport")
                    Text(verbatim: name)
                        .typography(.h1)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.lg) { stats(row, total: total) }
                VStack(alignment: .leading, spacing: Spacing.md) { stats(row, total: total) }
            }
            .redacted(reason: row == nil && !strength.loadFailed ? .placeholder : [])
            Text("Mobility = visa-free + visa on arrival. Typical eligibility, not a promise of admission.")
                .typography(.xs)
                .foregroundStyle(Theme.textSoft)
        }
    }

    @ViewBuilder
    private func stats(_ row: PassportIndexRow?, total: Int) -> some View {
        PassportStat(label: "Rank",
                     value: row.map { "#\($0.rank)" } ?? "#00",
                     sub: row.map { _ in String(localized: "of \(total)") })
        PassportStat(label: "Visa-free",
                     value: row.map { "\($0.visaFree)" } ?? "000")
        PassportStat(label: "Mobility",
                     value: row.map { "\($0.mobilityScore)" } ?? "000",
                     sub: row.map { String(localized: "of \($0.known) destinations") })
    }

    private func breakdown(_ row: PassportIndexRow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Eyebrow(text: "Access by status")
                PassportStatusBar(counts: row.counts, height: 10)
                VStack(spacing: 0) {
                    ForEach(Array(PassportCounts.statuses.enumerated()), id: \.element) { i, status in
                        if i > 0 { RowDivider(inset: 0) }
                        HStack(spacing: Spacing.sm) {
                            MapSwatch(fill: status.mapFill)
                            Text(verbatim: status.label).typography(.sm).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(verbatim: "\(row.counts[status])")
                                .font(Typography.font(.monoSm))
                                .foregroundStyle(Theme.textBody)
                        }
                        .padding(.vertical, Spacing.sm)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var mapCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                WorldMapView(statuses: model.statuses, home: [iso2], onTap: { _ in })
                    .frame(height: 190)
                    .allowsHitTesting(false)
                    .overlay {
                        if model.loading && model.statuses.isEmpty { ProgressView() }
                    }
                Divider().overlay(Theme.border)
                MapLegend()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Access by entry status"))
    }

    @ViewBuilder
    private func stays(name: String) -> some View {
        let visible = showAllStays ? model.topVisaFree : Array(model.topVisaFree.prefix(8))
        if !model.topVisaFree.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Eyebrow(text: "Longest visa-free stays")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, stay in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: CatalogRoute.corridor(from: iso2, to: stay.iso2)) {
                                CatalogRow(
                                    title: stay.name,
                                    trailing: stay.daysAllowed.map { String(localized: "\($0) days") }
                                ) {
                                    CountryFlag(iso2: stay.iso2, size: 24)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if model.topVisaFree.count > visible.count {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showAllStays = true }
                    } label: {
                        Text("Show all \(model.topVisaFree.count)")
                            .typography(.sm)
                            .foregroundStyle(Theme.ink)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if model.failed {
            CatalogStateCard(kind: .failed) { Task { await model.load(iso2, countries: catalog.countries, force: true) } }
        }
    }

    private var compareLink: some View {
        let others = passports.passports.filter { $0 != iso2 }
        return NavigationLink(value: PassportRoute.compare([iso2] + others.prefix(1))) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.split.2x1")
                Text("Compare with another passport").typography(.sm)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .foregroundStyle(Theme.ink)
            .padding(Spacing.lg)
            .background(Theme.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
        .buttonStyle(.plain)
    }
}

/// The passport page's destination data: its `visa_requirements` slice
/// (cached), folded into the map's statuses and the top visa-free stays.
@MainActor
@Observable
final class PassportDetailModel {
    private(set) var statuses: [String: VisaStatus] = [:]
    private(set) var topVisaFree: [PassportFilters.Stay] = []
    private(set) var loading = false
    private(set) var failed = false

    private let repo: RequirementsRepository
    private var loadedISO: String?
    private var rows: [VisaRequirement] = []
    private var names: [String: String] = [:]

    init(repo: RequirementsRepository = RequirementsRepository()) {
        self.repo = repo
    }

    func load(_ iso2: String, countries: [Country], force: Bool = false) async {
        guard force || loadedISO != iso2 else { return }
        setNames(countries)
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

    /// Re-resolve names once the catalog arrives after the rows.
    func rename(_ countries: [Country]) {
        setNames(countries)
        apply(rows)
    }

    private func setNames(_ countries: [Country]) {
        var names: [String: String] = [:]
        for c in countries { names[c.iso2.uppercased()] = c.displayName }
        self.names = names
    }

    private func apply(_ rows: [VisaRequirement]) {
        self.rows = rows
        var statuses: [String: VisaStatus] = [:]
        for row in rows { statuses[row.destinationIso2.uppercased()] = row.status }
        self.statuses = statuses
        let names = names
        topVisaFree = PassportFilters.topVisaFree(rows) { names[$0] }
    }
}

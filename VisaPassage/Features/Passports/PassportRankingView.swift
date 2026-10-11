import SwiftUI

/// Screen 14: every ranked passport (web `/passports` "Full ranking"): flag,
/// rank, mobility score and visa-free count, with search, a region filter and
/// your own passports pinned on top. Rank is the dense rank from `DenseRank`,
/// the same numbers as the web.
struct PassportRankingView: View {
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(PassportPreference.self) private var passports

    @State private var query = ""
    @State private var region: String?

    var body: some View {
        let index = strength.index(countries: catalog.countries)
        let rows = PassportFilters.filter(index, region: region, query: query)
        let yours = passports.passports.compactMap { iso in rows.first { $0.iso2 == iso } }

        content(index: index, rows: rows, yours: yours)
            .background(Theme.bg)
            .navigationTitle("Passport ranking")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search a passport, e.g. Japan"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: PassportRoute.compare(passports.passports)) {
                        Text("Compare")
                    }
                }
            }
            .task { await strength.loadIfNeeded() }
            .refreshable { await strength.reload() }
    }

    @ViewBuilder
    private func content(index: [PassportIndexRow], rows: [PassportIndexRow], yours: [PassportIndexRow]) -> some View {
        if index.isEmpty {
            if strength.loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load the ranking", systemImage: "wifi.slash")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await strength.reload() } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No passport matches “\(query)”.")
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            } actions: {
                Button("Clear filters") {
                    query = ""
                    region = nil
                }
            }
        } else {
            List {
                // In the list, not pinned above it: a horizontal scroller right
                // under the nav bar is hidden by the iOS 26 scroll edge effect.
                RegionChips(regions: PassportFilters.regions(in: index), selection: $region)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)
                if !yours.isEmpty {
                    Section {
                        ForEach(yours) { row in link(row, isYours: true) }
                    } header: {
                        Eyebrow(text: "Your passports")
                    }
                }
                Section {
                    ForEach(rows) { row in link(row, isYours: passports.contains(row.iso2)) }
                } header: {
                    HStack {
                        Eyebrow(text: "Full ranking")
                        Spacer()
                        Text("\(rows.count) passports")
                            .typography(.xs)
                            .foregroundStyle(Theme.textSoft)
                    }
                } footer: {
                    Text("Mobility = visa-free + visa on arrival. Typical eligibility, not a promise of admission.")
                        .typography(.xs)
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func link(_ row: PassportIndexRow, isYours: Bool) -> some View {
        NavigationLink(value: PassportRoute.detail(row.iso2)) {
            PassportRankingRow(row: row, isYours: isYours)
        }
        .listRowBackground(Theme.bg)
        .listRowInsets(EdgeInsets(top: 10, leading: Spacing.lg, bottom: 10, trailing: Spacing.lg))
    }
}

/// One ranking row. Equatable, so scrolling never re-renders unchanged rows.
struct PassportRankingRow: View, Equatable {
    let row: PassportIndexRow
    let isYours: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: "\(row.rank)")
                .font(Typography.font(.monoSm))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 30, alignment: .leading)
            CountryFlag(iso2: row.iso2, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.xs) {
                    Text(verbatim: row.name)
                        .typography(.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if isYours {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSoft)
                            .accessibilityLabel(Text("Your passport"))
                    }
                }
                PassportStatusBar(counts: row.counts)
                Text("\(row.visaFree) visa-free")
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(row.mobilityScore)")
                    .font(Typography.font(.monoBody))
                    .foregroundStyle(Theme.ink)
                Text("mobility")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

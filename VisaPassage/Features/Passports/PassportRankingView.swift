import SwiftUI

/// Screen 14: every ranked passport (web `/passports` "Full ranking",
/// `PassportLeaderboard.tsx`): region pills, sort, the status legend, and one
/// row per passport with rank, flag, name, the status bar and the mobility
/// score. Phones get the web's two-line phone grid; iPad and wide landscape get
/// its five-column grid with a pinned column header. Rank is the dense rank
/// from `DenseRank`, the same numbers as the web.
struct PassportRankingView: View {
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(PassportPreference.self) private var passports
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var query = ""
    @State private var region: String?
    @State private var sort: PassportFilters.Sort = .rank
    @State private var explained: VisaStatus?
    @State private var width: CGFloat = 0

    /// The web switches grids at `md` (768px); landscape Pro Max phones qualify too.
    private var layout: PassportRankingRow.Layout {
        sizeClass == .regular || width >= 720 ? .wide : .compact
    }

    var body: some View {
        let index = strength.index(countries: catalog.countries)
        let filtered = PassportFilters.filter(index, region: region, query: query)
        let rows = PassportFilters.sort(filtered, by: sort)
        let yours = passports.passports.compactMap { iso in index.first { $0.iso2 == iso } }

        content(index: index, rows: rows, yours: yours)
            .background(Theme.bg)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .navigationTitle("Passport ranking")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search a passport, e.g. Japan"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: PassportRoute.compare(passports.passports)) {
                        Text("Compare")
                    }
                    .accessibilityIdentifier("ranking.compare")
                }
            }
            .statusExplainer($explained)
            .task { await strength.loadIfNeeded() }
            .refreshable { await strength.reload() }
    }

    @ViewBuilder
    private func content(index: [PassportIndexRow], rows: [PassportIndexRow], yours: [PassportIndexRow]) -> some View {
        if index.isEmpty, strength.loadFailed {
            ContentUnavailableView {
                Label("Couldn't load the ranking", systemImage: "wifi.slash")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try again") { Task { await strength.reload() } }
            }
        } else {
            List {
                header(index: index)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)

                if index.isEmpty {
                    skeleton
                } else if rows.isEmpty {
                    empty
                } else {
                    if !yours.isEmpty, query.isEmpty {
                        Section {
                            ForEach(yours) { row in link(row, isYours: true) }
                        } header: {
                            sectionLabel("Your passports")
                        }
                    }
                    Section {
                        ForEach(rows) { row in link(row, isYours: passports.contains(row.iso2)) }
                    } header: {
                        columnHeader(count: rows.count)
                    } footer: {
                        Text("Mobility score = visa-free + visa-on-arrival destinations. Counts describe typical eligibility, never a promise of admission.")
                            .typography(.xs)
                            .foregroundStyle(Theme.textSoft)
                            .padding(.horizontal, gutter)
                            .padding(.vertical, Spacing.lg)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollDismissesKeyboard(.immediately)
            .animation(.snappy(duration: 0.25), value: sort)
            .animation(.snappy(duration: 0.25), value: region)
        }
    }

    private var gutter: CGFloat { layout == .wide ? Spacing.xl : Spacing.lg }

    // MARK: - Header

    private func header(index: [PassportIndexRow]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Select a passport to view its access map, longest visa-free stays and suggested second passports.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, gutter)

            RegionChips(regions: PassportFilters.regions(in: index), selection: $region, horizontalPadding: gutter)

            ViewThatFits(in: .horizontal) {
                SortSegmented(selection: $sort).frame(maxWidth: 420)
                SortSegmented(selection: $sort)
            }
            .padding(.horizontal, gutter)

            StatusLegend(spacing: 14) { explained = $0 }
                .padding(.horizontal, gutter)
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pinned under the nav bar while the ranking scrolls (web column grid).
    private func columnHeader(count: Int) -> some View {
        HStack(spacing: layout == .wide ? Spacing.lg : Spacing.md) {
            Text("#").frame(width: layout.rankWidth, alignment: .leading)
            HStack(spacing: 6) {
                Text("Passport")
                Text(verbatim: "\(count)")
                    .font(Typography.font(.monoSm))
                    .tracking(0)
                    .accessibilityIdentifier("ranking.count")
            }
            .frame(maxWidth: layout == .wide ? PassportRankingRow.nameMaxWidth : .infinity, alignment: .leading)
            if layout == .wide {
                Text("Access by status").frame(maxWidth: .infinity, alignment: .leading)
                Text("Visa-free").frame(width: 104, alignment: .trailing)
            }
            Text("Mobility")
                .fixedSize()
                .frame(width: layout.scoreWidth, alignment: .trailing)
        }
        .font(.custom("Geist-Medium", size: 10.5))
        .tracking(1.4)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textSoft)
        .lineLimit(1)
        .padding(.horizontal, gutter)
        .padding(.trailing, PassportRankingRow.chevronWidth)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) passports"))
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
        .listRowInsets(EdgeInsets())
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Eyebrow(text: text)
            .padding(.horizontal, gutter)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg)
            .listRowInsets(EdgeInsets())
    }

    // MARK: - Rows

    private func link(_ row: PassportIndexRow, isYours: Bool) -> some View {
        NavigationLink(value: PassportRoute.detail(row.iso2)) {
            PassportRankingRow(row: row, isYours: isYours, layout: layout)
        }
        .listRowBackground(Theme.bg)
        .listRowSeparatorTint(Theme.border)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .listRowInsets(EdgeInsets(top: 14, leading: gutter, bottom: 14, trailing: gutter))
    }

    private var skeleton: some View {
        ForEach(0..<8, id: \.self) { _ in
            PassportRankingRow(row: .placeholder, isYours: false, layout: layout)
                .redacted(reason: .placeholder)
                .listRowBackground(Theme.bg)
                .listRowInsets(EdgeInsets(top: 14, leading: gutter, bottom: 14, trailing: gutter))
        }
        .accessibilityHidden(true)
    }

    private var empty: some View {
        VStack(spacing: Spacing.md) {
            Text("No passport matches “\(query)”.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
            Button {
                query = ""
                region = nil
                sort = .rank
            } label: {
                Text("Clear filters")
                    .typography(.sm)
                    .foregroundStyle(Theme.ink)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxxl)
        .listRowBackground(Theme.bg)
        .listRowSeparator(.hidden)
    }
}

/// One ranking row (web leaderboard `<li>`). Equatable, so scrolling never
/// re-renders unchanged rows; the layout comes from the list, not a per-row
/// geometry read.
struct PassportRankingRow: View, Equatable {
    enum Layout: Equatable {
        /// Web phone grid: `rank | flag + name (bar below) | score`.
        case compact
        /// Web md grid: `rank | flag + name | bar | visa-free | score`.
        case wide

        var rankWidth: CGFloat { self == .wide ? 40 : 30 }
        var scoreWidth: CGFloat { self == .wide ? 64 : 52 }
    }

    static let nameMaxWidth: CGFloat = 240
    /// The List's disclosure chevron, so the column header lines up with the cells.
    static let chevronWidth: CGFloat = 20

    let row: PassportIndexRow
    let isYours: Bool
    let layout: Layout

    var body: some View {
        Group {
            switch layout {
            case .compact: compact
            case .wide: wide
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityIdentifier("ranking.row.\(row.iso2)")
    }

    private var compact: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            rank
            VStack(alignment: .leading, spacing: 8) {
                identity
                PassportStatusBar(counts: row.counts, size: .sm)
                    .padding(.leading, 34)
            }
            score
        }
    }

    private var wide: some View {
        HStack(spacing: Spacing.lg) {
            rank
            identity.frame(maxWidth: Self.nameMaxWidth, alignment: .leading)
            PassportStatusBar(counts: row.counts, size: .md)
                .frame(maxWidth: .infinity)
            Text("\(row.visaFree) visa-free")
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .frame(width: 104, alignment: .trailing)
            score
        }
    }

    private var rank: some View {
        Text(verbatim: "\(row.rank)")
            .font(Typography.font(.monoSm))
            .monospacedDigit()
            .foregroundStyle(Theme.textSoft)
            .frame(width: layout.rankWidth, alignment: .leading)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            CountryFlag(iso2: row.iso2, size: 24)
            Text(verbatim: row.name)
                .font(.custom("Geist-Medium", size: 15, relativeTo: .body))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if isYours {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var score: some View {
        Text(verbatim: "\(row.mobilityScore)")
            .font(Typography.font(.monoBody))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .frame(width: layout.scoreWidth, alignment: .trailing)
    }

    private var accessibilityText: String {
        var parts = [
            String(localized: "Rank \(row.rank)"),
            row.name,
            String(localized: "mobility \(row.mobilityScore)"),
            String(localized: "\(row.visaFree) visa-free"),
        ]
        if isYours { parts.append(String(localized: "Your passport")) }
        return parts.joined(separator: ", ")
    }
}

extension PassportIndexRow {
    /// Skeleton content while the ranking loads.
    static let placeholder = PassportIndexRow(
        iso2: "XX", name: "Placeholder name", englishName: "", slug: "", region: nil,
        rank: 100, mobilityScore: 100, known: 200,
        counts: PassportCounts(visaFree: 90, visaOnArrival: 20, evisa: 30, eta: 5, visaRequired: 50, noAdmission: 0)
    )
}

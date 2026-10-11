import SwiftUI

/// Screen 16: 2–4 passports side by side (web `/passports/compare` and the pair
/// page `/passports/compare/{a}-vs-{b}`). Combined mobility, each passport's
/// rank and status bar, the "Side by side" scoreboard, the regional split (for
/// two), the combined breakdown, and every destination where one passport is
/// easier. Data: `GET /api/passports?codes=` plus the shared ranking.
struct PassportCompareView: View {
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var codes: [String]
    @State private var model = PassportCompareModel()
    @State private var picking = false
    @State private var explained: VisaStatus?
    @State private var expanded: Set<String> = []
    @State private var width: CGFloat = 0

    /// Web `COMPARE_PASSPORTS`: the picker's curated passports, before the rest by rank.
    static let curated = ["US", "GB", "DE", "IN", "CA", "AU", "FR", "IT", "ES", "NL",
                          "IE", "CH", "JP", "KR", "SG", "NZ", "CN", "BR", "MX", "AE"]

    init(initialCodes: [String]) {
        _codes = State(initialValue: PassportRankingRepository.normalize(initialCodes))
    }

    private var isFull: Bool { codes.count >= PassportRankingRepository.maxCompare }
    private var wide: Bool { sizeClass == .regular || width >= 720 }
    private var gutter: CGFloat { wide ? Spacing.xxl : Spacing.lg }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                selection
                results
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, Spacing.lg)
            .readableWidth()
        }
        .background(Theme.bg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .centredDialog(isPresented: $picking, maxWidth: 480, fillsHeight: true) { close in
            picker(close: close)
        }
        .statusExplainer($explained)
        .task { await strength.loadIfNeeded() }
        .task(id: codes) { await model.load(codes) }
    }

    // MARK: - Selection

    private var selection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Select two to four passports to see their combined access and which passport covers each destination.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: Spacing.sm) {
                ForEach(codes, id: \.self) { iso in
                    let label = name(iso) ?? iso
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { codes.removeAll { $0 == iso } }
                    } label: {
                        HStack(spacing: 6) {
                            CountryFlag(iso2: iso, size: 20)
                            Text(verbatim: label).typography(.sm).lineLimit(1)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .frame(height: 36)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(label)"))
                }
                if !isFull {
                    Button { picking = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            Text("Add a passport…").typography(.sm)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compare.add")
                }
            }
            if isFull {
                Text("Maximum of 4 passports. Remove one to add another.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            }
        }
    }

    private func picker(close: @escaping () -> Void) -> some View {
        let index = strength.index(countries: catalog.countries)
        let ranked = Set(index.map(\.iso2))
        let order = Dictionary(uniqueKeysWithValues: index.enumerated().map { ($1.iso2, $0) })
        let countries = catalog.countries
            .filter { ranked.contains($0.iso2.uppercased()) }
            .sorted { (order[$0.iso2.uppercased()] ?? .max) < (order[$1.iso2.uppercased()] ?? .max) }
        return NavigationStack {
            CountryListPicker(
                countries: countries,
                selected: codes,
                suggested: Self.curated.filter { !codes.contains($0) },
                isDisabled: { c in isFull && !codes.contains(c.iso2.uppercased()) }
            ) { country in
                let iso = country.iso2.uppercased()
                if codes.contains(iso) {
                    codes.removeAll { $0 == iso }
                } else if !isFull {
                    codes = PassportRankingRepository.normalize(codes + [iso])
                    if codes.count >= PassportRankingRepository.maxCompare { close() }
                }
            }
            .navigationTitle("Add a passport…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if codes.count < 2 {
            CatalogStateCard(kind: .empty, message: String(localized: "Pick at least two passports to compare them."))
        } else if let c = model.comparison(for: codes, name: name), c.passports.count >= 2 {
            let sides = sides(c)
            combined(c)
            passportBars(c, sides: sides)
            scoreboard(sides)
            if c.passports.count == 2 { regions(c) }
            combinedBreakdown(c)
            differences(c)
            Text("Combined coverage takes the least-restrictive status across the selected passports for each destination. Figures describe typical eligibility, never a promise of admission.")
                .typography(.xs)
                .foregroundStyle(Theme.textSoft)
        } else if model.failed {
            CatalogStateCard(kind: .failed, message: String(localized: "We couldn’t load those passports. Try picking from the list above.")) {
                Task { await model.load(codes, force: true) }
            }
        } else {
            CatalogStateCard(kind: .loading, message: String(localized: "Loading passports…"))
        }
    }

    /// One scoreboard column: the ranking's numbers when the passport is
    /// ranked (identical to the web), else the compare slice's own.
    struct Side: Identifiable {
        var iso2: String
        var name: String
        var rank: Int
        var mobility: Int
        var counts: PassportCounts
        var id: String { iso2 }
    }

    private func sides(_ c: PassportComparison) -> [Side] {
        let index = strength.index(countries: catalog.countries)
        return c.passports.map { p in
            let row = index.first { $0.iso2 == p.iso2.uppercased() }
            var counts = PassportCounts(visaFree: 0, visaOnArrival: 0, evisa: 0, eta: 0, visaRequired: 0, noAdmission: 0)
            if let row {
                counts = row.counts
            } else {
                for r in p.requirements {
                    switch r.status {
                    case .visaFree: counts.visaFree += 1
                    case .visaOnArrival: counts.visaOnArrival += 1
                    case .evisa: counts.evisa += 1
                    case .eta: counts.eta += 1
                    case .visaRequired: counts.visaRequired += 1
                    case .noAdmission: counts.noAdmission += 1
                    case .unknown: break
                    }
                }
            }
            return Side(iso2: p.iso2.uppercased(), name: name(p.iso2) ?? p.name,
                        rank: row?.rank ?? p.rank, mobility: row?.mobilityScore ?? p.mobilityScore, counts: counts)
        }
    }

    private func combined(_ c: PassportComparison) -> some View {
        let best = c.passports.max { $0.mobilityScore < $1.mobilityScore }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Eyebrow(text: "Combined mobility")
            Text(verbatim: "\(c.combinedMobility)")
                .font(.custom("GeistMono-Regular", size: wide ? 56 : 44, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text("visa-free or on arrival")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
            if let best, c.combinedMobility > c.bestSingle {
                Text("+\(c.combinedMobility - c.bestSingle) over the strongest single passport (\(name(best.iso2) ?? best.name))")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, Spacing.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func passportBars(_ c: PassportComparison, sides: [Side]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(spacing: 0) {
                ForEach(Array(sides.enumerated()), id: \.element.id) { i, side in
                    if i > 0 { RowDivider(inset: 0) }
                    NavigationLink(value: PassportRoute.detail(side.iso2)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: Spacing.md) {
                                CountryFlag(iso2: side.iso2, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: side.name)
                                        .typography(.sm)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Text("leads on \(c.leads[c.passports[i].iso2] ?? 0) destinations")
                                        .typography(.xs)
                                        .foregroundStyle(Theme.textSoft)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: Spacing.sm)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(verbatim: "\(side.mobility)")
                                        .font(Typography.font(.monoBody))
                                        .foregroundStyle(Theme.ink)
                                    Text(verbatim: "#\(side.rank)")
                                        .font(Typography.font(.monoSm))
                                        .foregroundStyle(Theme.textSoft)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            PassportStatusBar(counts: side.counts, size: .md)
                        }
                        .padding(Spacing.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .hairlineCard()
            StatusLegend { explained = $0 }
        }
    }

    // MARK: - Scoreboard

    private struct Metric: Identifiable {
        let label: String
        let status: VisaStatus?
        let lowerIsBetter: Bool
        let values: [Int]
        let format: (Int) -> String
        var id: String { label }
    }

    private func metrics(_ sides: [Side]) -> [Metric] {
        var rows = [
            Metric(label: String(localized: "Rank"), status: nil, lowerIsBetter: true,
                   values: sides.map(\.rank), format: { "#\($0)" }),
            Metric(label: String(localized: "Mobility score"), status: nil, lowerIsBetter: false,
                   values: sides.map(\.mobility), format: { "\($0)" }),
        ]
        for status in PassportCounts.statuses {
            rows.append(Metric(label: status.shortLabel, status: status,
                               lowerIsBetter: status == .visaRequired || status == .noAdmission,
                               values: sides.map { $0.counts[status] }, format: { "\($0)" }))
        }
        return rows
    }

    private func scoreboard(_ sides: [Side]) -> some View {
        let available = min(width, 960) - gutter * 2
        // Too narrow for a label column plus every passport: the label moves above its values.
        let stacked = available < 132 + CGFloat(sides.count) * 64
        let metrics = metrics(sides)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            PassportSectionTitle(title: String(localized: "Side by side"))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if !stacked {
                        Text("Measure")
                            .frame(width: 132, alignment: .leading)
                    }
                    ForEach(sides) { side in
                        VStack(spacing: 4) {
                            CountryFlag(iso2: side.iso2, size: 22)
                            Text(verbatim: side.name)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .font(.custom("Geist-Medium", size: 11))
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .background(Theme.surface)

                ForEach(metrics) { metric in
                    RowDivider(inset: 0)
                    let winners = PassportComparison.winners(metric.values, lowerIsBetter: metric.lowerIsBetter)
                    VStack(alignment: .leading, spacing: 6) {
                        if stacked { metricLabel(metric) }
                        HStack(spacing: 0) {
                            if !stacked { metricLabel(metric).frame(width: 132, alignment: .leading) }
                            ForEach(Array(metric.values.enumerated()), id: \.offset) { i, value in
                                let lead = winners.contains(i)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Theme.ink)
                                        .frame(width: 6, height: 6)
                                        .opacity(lead ? 1 : 0)
                                    Text(verbatim: metric.format(value))
                                        .font(.custom(lead ? "GeistMono-Medium" : "GeistMono-Regular", size: 15,
                                                      relativeTo: .body))
                                        .monospacedDigit()
                                        .foregroundStyle(lead ? Theme.ink : Theme.textSoft)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: "\(sides[i].name): \(metric.format(value))"))
                                .accessibilityValue(lead ? Text("Leads") : Text(verbatim: ""))
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, stacked ? 10 : 12)
                }
            }
            .hairlineCard()
        }
    }

    private func metricLabel(_ metric: Metric) -> some View {
        HStack(spacing: 6) {
            if let status = metric.status { StatusKeyIcon(status, size: 14) }
            Text(verbatim: metric.label)
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
        }
    }

    // MARK: - Regions

    private func regions(_ c: PassportComparison) -> some View {
        let tallies = c.regionTallies { catalog.country($0)?.region }.filter { $0.total > 0 }
        let a = c.passports[0].iso2, b = c.passports[1].iso2
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            PassportSectionTitle(
                title: String(localized: "Visa-free or on arrival, by region"),
                lede: String(localized: "Destinations each passport reaches without applying in advance, per continent.")
            )
            HStack {
                legendFlag(a)
                Spacer()
                legendFlag(b)
            }
            VStack(spacing: Spacing.md) {
                ForEach(tallies, id: \.region) { t in
                    let ca = t.counts[0], cb = t.counts[1]
                    VStack(spacing: 6) {
                        HStack {
                            Text(verbatim: "\(ca)").font(Typography.font(.monoSm)).foregroundStyle(Theme.ink)
                            Spacer()
                            VStack(spacing: 0) {
                                Text(verbatim: PassportFilters.regionTitle(t.region))
                                    .typography(.xs)
                                    .foregroundStyle(Theme.ink)
                                Text("of \(t.total)")
                                    .font(.custom("Geist-Regular", size: 11))
                                    .foregroundStyle(Theme.textSoft)
                            }
                            Spacer()
                            Text(verbatim: "\(cb)").font(Typography.font(.monoSm)).foregroundStyle(Theme.ink)
                        }
                        HStack(spacing: 2) {
                            bar(ca, of: t.total, leads: ca >= cb, leading: false)
                            bar(cb, of: t.total, leads: cb >= ca, leading: true)
                        }
                        .frame(height: 8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(PassportFilters.regionTitle(t.region)): \(name(a) ?? a) \(ca), \(name(b) ?? b) \(cb) / \(t.total)"))
                }
            }
            .padding(Spacing.lg)
            .hairlineCard()
        }
    }

    private func legendFlag(_ iso: String) -> some View {
        HStack(spacing: 6) {
            CountryFlag(iso2: iso, size: 18)
            Text(verbatim: name(iso) ?? iso).typography(.xs).foregroundStyle(Theme.textBody).lineLimit(1)
        }
    }

    /// Half of a mirrored bar: A grows left from the centre, B grows right.
    private func bar(_ value: Int, of total: Int, leads: Bool, leading: Bool) -> some View {
        GeometryReader { geo in
            let w = total > 0 ? geo.size.width * CGFloat(value) / CGFloat(total) : 0
            ZStack(alignment: leading ? .leading : .trailing) {
                Capsule().fill(Theme.surface2)
                Capsule().fill(Theme.ink.opacity(leads ? 1 : 0.35)).frame(width: w)
            }
        }
    }

    // MARK: - Combined breakdown

    private func combinedBreakdown(_ c: PassportComparison) -> some View {
        let counts = PassportCounts(
            visaFree: c.counts[.visaFree] ?? 0, visaOnArrival: c.counts[.visaOnArrival] ?? 0,
            evisa: c.counts[.evisa] ?? 0, eta: c.counts[.eta] ?? 0,
            visaRequired: c.counts[.visaRequired] ?? 0, noAdmission: c.counts[.noAdmission] ?? 0
        )
        let columns = width >= 900 ? 6 : (width >= 560 ? 3 : 2)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            PassportSectionTitle(
                title: codes.count == 2 ? String(localized: "Holding both") : String(localized: "Holding them together"),
                lede: String(localized: "The easier status at each border, destination by destination.")
            )
            PassportStatusBar(counts: counts, size: .lg)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Hairline.width), count: columns),
                      spacing: Hairline.width) {
                ForEach(PassportCounts.statuses, id: \.self) { status in
                    Button { explained = status } label: {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            StatusKeyIcon(status, size: 20)
                            Text(verbatim: "\(counts[status])")
                                .font(.custom("GeistMono-Regular", size: 24, relativeTo: .title2))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: status.shortLabel)
                                .typography(.xs)
                                .foregroundStyle(Theme.textBody)
                                .lineLimit(1)
                        }
                        .opacity(counts[status] == 0 ? 0.45 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.lg)
                        .background(Theme.bg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Theme.border)
            .hairlineCard()
        }
    }

    // MARK: - Where they differ

    private func differences(_ c: PassportComparison) -> some View {
        let groups = c.passports.indices.map { i in (i, c.easier(with: i)) }
        let columns = wide ? 2 : 1
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            PassportSectionTitle(
                title: String(localized: "Where they differ"),
                lede: String(localized: "\(c.sameCount) destinations treat every passport the same. These are the ones that don’t.")
            )
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.lg, alignment: .top), count: columns),
                      alignment: .leading, spacing: Spacing.lg) {
                ForEach(groups, id: \.0) { i, rows in
                    diffGroup(c, holder: i, rows: rows)
                }
            }
        }
    }

    private func diffGroup(_ c: PassportComparison, holder i: Int, rows: [PassportComparison.DiffRow]) -> some View {
        let iso = c.passports[i].iso2
        let holderName = name(iso) ?? c.passports[i].name
        let isOpen = expanded.contains(iso)
        let visible = isOpen ? rows : Array(rows.prefix(12))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                CountryFlag(iso2: iso, size: 20)
                Text("Easier with \(holderName)")
                    .typography(.sm)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: Spacing.sm)
                Text(verbatim: "\(rows.count)")
                    .font(Typography.font(.monoSm))
                    .foregroundStyle(Theme.textSoft)
            }
            .padding(Spacing.lg)
            .background(Theme.surface)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if rows.isEmpty {
                RowDivider(inset: 0)
                Text("No destination is easier with \(holderName).")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVStack(spacing: 0) {
                ForEach(visible) { row in
                    RowDivider(inset: 0)
                    NavigationLink(value: CatalogRoute.corridor(from: iso, to: row.iso2)) {
                        DiffRowView(row: row, holder: i, passports: c.passports.map(\.iso2))
                    }
                    .buttonStyle(.plain)
                }
            }
            if rows.count > visible.count {
                RowDivider(inset: 0)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { _ = expanded.insert(iso) }
                } label: {
                    Text("Show all \(rows.count)")
                        .typography(.sm)
                        .foregroundStyle(Theme.ink)
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .hairlineCard()
    }

    private func name(_ iso2: String) -> String? {
        catalog.name(forISO2: iso2)
    }
}

/// One destination in an "Easier with" group: the holder's status in full,
/// the other passports' statuses on a smaller line below.
private struct DiffRowView: View {
    let row: PassportComparison.DiffRow
    let holder: Int
    let passports: [String]

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            CountryFlag(iso2: row.iso2, size: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name)
                    .typography(.sm)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                // One line per other passport; with two passports just the status.
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(passports.indices.filter { $0 != holder }, id: \.self) { j in
                        HStack(spacing: 4) {
                            if passports.count > 2 { CountryFlag(iso2: passports[j], size: 12) }
                            StatusCell(status: row.statuses[j], days: nil, iconSize: 12)
                        }
                        .opacity(0.75)
                    }
                }
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                StatusCell(status: row.statuses[holder], iconSize: 16)
                if let days = row.days.indices.contains(holder) ? row.days[holder] : nil {
                    Text("\(days) days")
                        .font(Typography.font(.monoSm))
                        .foregroundStyle(Theme.textSoft)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Hairline-bordered clip at the web's 20px card radius.
    func hairlineCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width))
    }
}

/// Loads the compare slices for one selection (cached per sorted code set).
@MainActor
@Observable
final class PassportCompareModel {
    private(set) var passports: [ComparePassport] = []
    private(set) var loadedKey: [String] = []
    private(set) var failed = false

    private let repo: PassportRankingRepository
    /// The selection last asked for; a late refresh for another one is dropped.
    @ObservationIgnored private var requested: [String] = []
    @ObservationIgnored private var memo: (key: [String], value: PassportComparison)?

    init(repo: PassportRankingRepository = PassportRankingRepository()) {
        self.repo = repo
    }

    func load(_ codes: [String], force: Bool = false) async {
        let key = PassportRankingRepository.normalize(codes)
        requested = key
        guard key.count >= 2, force || key != loadedKey else { return }
        failed = false
        do {
            let fresh = try await repo.compare(key) { [weak self] fresh in
                await self?.apply(fresh, key: key)
            }
            apply(fresh, key: key)
        } catch {
            if requested == key { failed = true }
        }
    }

    private func apply(_ fresh: [ComparePassport], key: [String]) {
        guard key == requested else { return }
        passports = fresh
        loadedKey = key
        memo = nil
    }

    /// The comparison for the current selection, or nil while it loads.
    func comparison(for codes: [String], name: (String) -> String?) -> PassportComparison? {
        let key = PassportRankingRepository.normalize(codes)
        guard key == loadedKey else { return nil }
        if let memo, memo.key == key { return memo.value }
        let value = PassportComparison(passports, name: name)
        memo = (key, value)
        return value
    }
}

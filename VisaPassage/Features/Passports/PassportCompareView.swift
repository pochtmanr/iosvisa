import SwiftUI

/// Screen 16: 2–4 passports side by side (web `/passports/compare`). Combined
/// mobility, each passport's rank and lead, the combined breakdown, and every
/// destination where the passports differ. Data: `GET /api/passports?codes=`.
struct PassportCompareView: View {
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog

    @State private var codes: [String]
    @State private var model = PassportCompareModel()
    @State private var picking = false

    init(initialCodes: [String]) {
        _codes = State(initialValue: PassportRankingRepository.normalize(initialCodes))
    }

    private var isFull: Bool { codes.count >= PassportRankingRepository.maxCompare }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                selection
                results
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle("Compare passports")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) { picker }
        .task { await strength.loadIfNeeded() }
        .task(id: codes) { await model.load(codes) }
    }

    // MARK: - Selection

    private var selection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select two to four passports to see their combined access and which passport covers each destination.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
            FlowChips(codes: codes, name: name) { iso in
                codes.removeAll { $0 == iso }
            }
            if isFull {
                Text("Maximum of 4 passports. Remove one to add another.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            } else {
                Button { picking = true } label: {
                    Label("Add a passport…", systemImage: "plus")
                        .typography(.sm)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var picker: some View {
        let ranked = Set(strength.index(countries: catalog.countries).map(\.iso2))
        return NavigationStack {
            CountryListPicker(
                countries: catalog.countries.filter { ranked.contains($0.iso2.uppercased()) },
                selected: codes,
                isDisabled: { _ in isFull }
            ) { country in
                let iso = country.iso2.uppercased()
                if codes.contains(iso) {
                    codes.removeAll { $0 == iso }
                } else if !isFull {
                    codes = PassportRankingRepository.normalize(codes + [iso])
                }
            }
            .navigationTitle("Add a passport…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { picking = false }
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if codes.count < 2 {
            CatalogStateCard(kind: .empty, message: String(localized: "Pick at least two passports to compare them."))
        } else if let comparison = model.comparison(for: codes, name: name), comparison.passports.count >= 2 {
            summary(comparison)
            passportCards(comparison)
            combinedBreakdown(comparison)
            differences(comparison)
            Text("Combined coverage takes the least-restrictive status across the selected passports for each destination. Figures describe typical eligibility, not a promise of admission.")
                .typography(.xs)
                .foregroundStyle(Theme.textSoft)
        } else if model.failed {
            CatalogStateCard(kind: .failed, message: String(localized: "We couldn’t load those passports. Try picking from the list above.")) {
                Task { await model.load(codes, force: true) }
            }
        } else {
            Card {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("Loading passports…").typography(.sm).foregroundStyle(Theme.textBody)
                }
            }
        }
    }

    private func summary(_ c: PassportComparison) -> some View {
        let best = c.passports.max { $0.mobilityScore < $1.mobilityScore }
        return Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Eyebrow(text: "Combined mobility")
                Text(verbatim: "\(c.combinedMobility)")
                    .typography(.display)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
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
        }
    }

    private func passportCards(_ c: PassportComparison) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(c.passports.enumerated()), id: \.element.iso2) { i, p in
                    if i > 0 { RowDivider() }
                    NavigationLink(value: PassportRoute.detail(p.iso2)) {
                        CatalogRow(
                            title: name(p.iso2) ?? p.name,
                            subtitle: String(localized: "#\(p.rank) · mobility \(p.mobilityScore)") + " · "
                                + String(localized: "leads on \(c.leads[p.iso2] ?? 0) destinations"),
                            trailing: nil
                        ) {
                            CountryFlag(iso2: p.iso2, size: 28)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func combinedBreakdown(_ c: PassportComparison) -> some View {
        let counts = PassportCounts(
            visaFree: c.counts[.visaFree] ?? 0, visaOnArrival: c.counts[.visaOnArrival] ?? 0,
            evisa: c.counts[.evisa] ?? 0, eta: c.counts[.eta] ?? 0,
            visaRequired: c.counts[.visaRequired] ?? 0, noAdmission: c.counts[.noAdmission] ?? 0
        )
        return Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Eyebrow(text: "Access by status")
                PassportStatusBar(counts: counts, height: 10)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Spacing.sm) {
                    ForEach(PassportCounts.statuses, id: \.self) { status in
                        HStack(spacing: Spacing.xs) {
                            StatusCell(status: status)
                            Text(verbatim: "\(counts[status])")
                                .font(Typography.font(.monoSm))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
    }

    private func differences(_ c: PassportComparison) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: "Where they differ")
            Text("\(c.sameCount) destinations treat every passport the same. These are the ones that don’t.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
            if !c.differing.isEmpty {
                Card(padding: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(c.differing.enumerated()), id: \.element.id) { i, row in
                            if i > 0 { RowDivider() }
                            DiffRowView(row: row, passports: c.passports.map(\.iso2))
                        }
                    }
                }
            }
        }
    }

    private func name(_ iso2: String) -> String? {
        catalog.name(forISO2: iso2)
    }
}

/// One destination: its name, then each passport's status (flag + pill).
private struct DiffRowView: View {
    let row: PassportComparison.DiffRow
    let passports: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                CountryFlag(iso2: row.iso2, size: 20)
                Text(verbatim: row.name).typography(.sm).foregroundStyle(Theme.ink)
            }
            HStack(spacing: Spacing.md) {
                ForEach(Array(zip(passports, row.statuses)), id: \.0) { iso, status in
                    HStack(spacing: Spacing.xs) {
                        CountryFlag(iso2: iso, size: 14)
                        StatusCell(status: status)
                    }
                    .opacity(status == row.best ? 1 : 0.6)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// The selected passports as removable chips, wrapping onto a second line.
private struct FlowChips: View {
    let codes: [String]
    let name: (String) -> String?
    let onRemove: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { chips }
            VStack(alignment: .leading, spacing: Spacing.sm) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(codes, id: \.self) { iso in
            let label = name(iso) ?? iso
            Button { onRemove(iso) } label: {
                HStack(spacing: Spacing.xs) {
                    CountryFlag(iso2: iso, size: 18)
                    Text(verbatim: label).typography(.sm).lineLimit(1)
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Spacing.md)
                .frame(height: 36)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(label)"))
        }
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

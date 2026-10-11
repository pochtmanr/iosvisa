import SwiftUI

/// The Home tab, guest/new state (web `dashboard-state.ts` "new"): your
/// passport's strength, a "Where to?" search into Explore, popular routes,
/// the latest rule changes and a "Track a visa" CTA. IOS-05 adds the active
/// and done tracker states.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TabRouter.self) private var tabs
    @Environment(ExploreSelection.self) private var explore
    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements

    @State private var showPassports = false
    @State private var changes = RuleChangesModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    PassportStrengthCard { showPassports = true }
                    WhereToField {
                        explore.startSearch()
                        tabs.selection = .explore
                    }
                    if passports.primary != nil {
                        PopularRoutes { iso in
                            explore.show(destination: iso)
                            tabs.selection = .explore
                        }
                    }
                    RuleChangesSection(model: changes)
                    EntryCard(
                        icon: "checklist",
                        title: "Track a visa application",
                        subtitle: "Pick a destination, then tick documents off as you collect them."
                    ) {
                        explore.mode = .map
                        tabs.selection = .explore
                    }
                    AdvisoryDisclaimer()
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .catalogDestinations()
            .passportDestinations()
            .refreshable { await changes.load(passport: passports.primary) }
            .sheet(isPresented: $showPassports) { PassportsSheet() }
            .task { await passports.seedFromAccountIfEmpty() }
            .task(id: passports.passports) {
                await requirements.load(passports.passports)
            }
            .task(id: passports.primary) { await changes.load(passport: passports.primary) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Eyebrow(verbatim: "VisaPassage")
            Group {
                if let name = auth.profile?.displayName {
                    Text("Welcome back, \(name).")
                } else if auth.isSignedIn {
                    Text("Welcome back.")
                } else {
                    Text("Where to next?")
                }
            }
            .typography(.display)
            .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Passport card

/// Rank #N, visa-free count and mobility score for one of your passports, the
/// same numbers as the web `/passports/[slug]` stat cards.
private struct PassportStrengthCard: View {
    let onEdit: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(ExploreSelection.self) private var explore
    @Environment(TabRouter.self) private var tabs

    /// Which of your passports the card shows (defaults to the primary).
    @State private var shown: String?

    var body: some View {
        Card {
            if let iso = current {
                content(iso)
            } else {
                empty
            }
        }
        .task { await strength.loadIfNeeded() }
    }

    private var current: String? {
        if let shown, passports.contains(shown) { return shown }
        return passports.primary
    }

    @ViewBuilder
    private func content(_ iso: String) -> some View {
        let rank = strength.rank(for: iso, countries: catalog.countries)
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Eyebrow(text: "Your passport")
                Spacer()
                Button("Edit", action: onEdit)
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            }

            if passports.passports.count > 1 {
                Picker("Passport", selection: Binding(get: { iso }, set: { shown = $0 })) {
                    ForEach(passports.passports, id: \.self) { code in
                        Text(catalog.name(forISO2: code) ?? code).tag(code)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: iso, size: 36)
                Text(catalog.name(forISO2: iso) ?? iso)
                    .typography(.h3)
                    .foregroundStyle(Theme.ink)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.lg) { stats(rank) }
                VStack(alignment: .leading, spacing: Spacing.md) { stats(rank) }
            }
            .redacted(reason: rank == nil && !strength.loadFailed ? .placeholder : [])

            if rank == nil && strength.loadFailed {
                Text("Couldn't load the ranking. Pull to refresh later.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            } else {
                Text("Mobility = visa-free + visa on arrival. Typical eligibility, not a promise of admission.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xl) { links(iso) }
                VStack(alignment: .leading, spacing: Spacing.md) { links(iso) }
            }
        }
    }

    @ViewBuilder
    private func links(_ iso: String) -> some View {
        NavigationLink(value: PassportRoute.detail(iso)) {
            linkLabel("Passport details")
        }
        .buttonStyle(.plain)
        Button {
            explore.mode = .map
            tabs.selection = .explore
        } label: {
            linkLabel("See where you can go")
        }
        .buttonStyle(.plain)
    }

    private func linkLabel(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title).typography(.sm).fixedSize()
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private func stats(_ rank: PassportRank?) -> some View {
        PassportStat(label: "Rank",
             value: rank.map { "#\($0.rank)" } ?? "#00",
             sub: rank.map { String(localized: "of \($0.totalRanked)") })
        PassportStat(label: "Visa-free",
             value: rank.map { "\($0.visaFree)" } ?? "000",
             sub: nil)
        PassportStat(label: "Mobility",
             value: rank.map { "\($0.mobilityScore)" } ?? "000",
             sub: rank.map { String(localized: "of \($0.known) destinations") })
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: "Your passport")
            Text("Pick your passport")
                .typography(.h3)
                .foregroundStyle(Theme.ink)
            Text("See its rank, where you can go visa-free, and what each trip needs.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
            Button(action: onEdit) {
                Text("Choose passport")
                    .typography(.sm)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 40)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(PressShrinkStyle())
        }
    }
}

// MARK: - Where to?

/// Looks like a search field; opens Explore's list with search focused.
private struct WhereToField: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSoft)
                Text("Where to?")
                    .typography(.body)
                    .foregroundStyle(Theme.textSoft)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 48)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
        .buttonStyle(PressShrinkStyle())
        .accessibilityLabel(Text("Where to?"))
        .accessibilityHint(Text("Search destinations"))
    }
}

// MARK: - Popular routes

/// A static, curated list of popular destinations with your status for each.
// TODO: replace with real trending corridors once the web records searches.
private struct PopularRoutes: View {
    let onSelect: (String) -> Void

    static let destinations = ["TR", "AE", "TH", "GE", "GB", "US", "JP", "DE", "FR", "IT", "ES", "EG"]

    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        let picks = Array(Self.destinations.filter { !passports.contains($0) }.prefix(6))
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: "Popular routes")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(picks.enumerated()), id: \.element) { index, iso in
                        if index > 0 { Divider().overlay(Theme.border).padding(.leading, 56) }
                        Button { onSelect(iso) } label: { row(iso) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ iso: String) -> some View {
        let row = requirements.row(for: iso)
        let status = row?.status ?? .unknown
        return HStack(spacing: Spacing.md) {
            CountryFlag(iso2: iso, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(catalog.name(forISO2: iso) ?? iso)
                    .typography(.body)
                    .foregroundStyle(Theme.ink)
                if let days = row?.daysAllowed, days > 0 {
                    Text("Up to \(days) days").typography(.xs).foregroundStyle(Theme.textBody)
                }
            }
            Spacer(minLength: Spacing.sm)
            if status == .unknown {
                Text(status.label).typography(.xs).foregroundStyle(Theme.textSoft)
            } else {
                StatusBadge(text: status.label, hue: status.hue)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }
}

// MARK: - Rule changes

/// The latest published rule changes for your passport (or all passports).
private struct RuleChangesSection: View {
    let model: RuleChangesModel

    @Environment(CountryStore.self) private var catalog
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Eyebrow(text: "Latest rule changes")
                Spacer()
                Button("See all") { openChanges() }
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if model.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
                    } else if model.changes.isEmpty {
                        Text(model.failed
                             ? "Couldn't load rule changes."
                             : "No published changes yet. New entries appear here as our team verifies them.")
                            .typography(.sm)
                            .foregroundStyle(Theme.textBody)
                            .padding(Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(model.changes.enumerated()), id: \.element.id) { index, change in
                            if index > 0 { Divider().overlay(Theme.border) }
                            Button { openChanges() } label: { row(change) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func row(_ change: PolicyChange) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if let hue = change.changeKind.hue {
                    StatusBadge(text: change.changeKind.label, hue: hue)
                } else {
                    Text(change.changeKind.label)
                        .typeRole(.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSoft)
                }
                Spacer()
                if let date = change.publishedDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .typography(.xs)
                        .foregroundStyle(Theme.textSoft)
                }
            }
            Text(change.localizedTitle())
                .typography(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: Spacing.xs) {
                CountryFlag(iso2: change.destinationIso2, size: 16)
                Text(catalog.name(forISO2: change.destinationIso2) ?? change.destinationIso2)
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func openChanges() {
        openURL(AppLocale.current.webURL(path: "/changes"))
    }
}

/// A tappable hairline card with an icon, a title and one line of help.
struct EntryCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).typography(.title).foregroundStyle(Theme.ink)
                        Text(subtitle).typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                }
            }
        }
        .buttonStyle(PressShrinkStyle())
    }
}

import SwiftUI

/// The Home tab, guest/new state (web `dashboard-state.ts` "new"), laid out as
/// the same inset grouped list as Account: the brand lockup, your passports, the trip purposes, the latest rule changes, and the web
/// dashboard's "Guides and tools". IOS-05 adds the active and done tracker
/// states.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TabRouter.self) private var tabs
    @Environment(ExploreSelection.self) private var explore
    @Environment(PassportPreference.self) private var passports

    @State private var showPassports = false
    @State private var changes = RuleChangesModel()
    @State private var webPage: WebPage?
    /// The passport with the full row (nil: the primary).
    @State private var shownPassport: String?
    @State private var metricsFor: String?
    @State private var passportDetail: String?

    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TabHeader(title: Text(verbatim: "VisaPassage"), logo: true)
                        .tabHeaderRow()
                }
                PassportsSection(shown: $shownPassport,
                                 onEdit: { showPassports = true },
                                 onInfo: { metricsFor = $0 },
                                 onDetail: { passportDetail = $0 })
                purposes
                RuleChangesSection(model: changes) { openWeb("/changes") }
                GuidesSection { openWeb($0) }
                Section {
                    Button {
                        explore.mode = .map
                        tabs.selection = .explore
                    } label: {
                        RowLabel(icon: "checklist",
                                 title: "Track a visa application",
                                 hint: "Pick a destination, then tick documents off as you collect them.")
                    }
                    .foregroundStyle(Theme.ink)
                } footer: {
                    Text("Guidance only — eligibility is indicative. Official authority decisions always prevail.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .catalogDestinations()
            .passportDestinations()
            .trackerDestinations()
            .refreshable { await changes.load(passport: passports.primary) }
            .navigationDestination(item: $passportDetail) { iso in PassportDetailView(iso2: iso) }
            .passportsEditor(isPresented: $showPassports)
            .centredDialog(item: $metricsFor, maxWidth: 360, surface: .glass) { iso, close in
                PassportMetricsDialog(
                    iso2: iso,
                    name: catalog.name(forISO2: iso) ?? iso,
                    rank: strength.rank(for: iso, countries: catalog.countries),
                    onClose: close
                )
            }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
            .task { await passports.seedFromAccountIfEmpty() }
            .task { await strength.loadIfNeeded() }
            .task {
                // Screenshots: `-debug.passportInfo YES` opens the metrics dialog.
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "debug.passportInfo") { metricsFor = passports.primary }
                #endif
            }
            .task(id: passports.primary) { await changes.load(passport: passports.primary) }
        }
    }

    /// "What's the trip for?" (web `PurposeWidget`): one row per purpose, each
    /// opening Explore's map with that purpose applied.
    private var purposes: some View {
        Section("What's the trip for?") {
            PurposeList(suggested: Purpose.fromGoals(auth.profile?.goal)) { purpose in
                explore.open(purpose: purpose)
                tabs.selection = .explore
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private func openWeb(_ path: String) {
        webPage = WebPage(url: AppLocale.current.webURL(path: path))
    }
}

// MARK: - Your passports

/// "Your passports" with Edit in the header, like an Account section. The
/// passport shown gets the full row (rank, visa-free, mobility and links); the
/// rest are compact rows under it, and tapping one brings it up.
private struct PassportsSection: View {
    @Binding var shown: String?
    let onEdit: () -> Void
    let onInfo: (String) -> Void
    let onDetail: (String) -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(CountryStore.self) private var catalog
    @Environment(ExploreSelection.self) private var explore
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        Section {
            if let iso = current {
                // Rows keep their slots (full first, compact after) and every
                // passport fills a slot at the same height, so a switch swaps
                // the content in place, without a crossfade or a re-layout.
                full(iso)
                ForEach(Array(others.enumerated()), id: \.offset) { _, iso in
                    Button {
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) { shown = iso }
                    } label: {
                        compact(iso)
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityHint(Text("Shows this passport's rank and visa-free count"))
                }
            } else {
                empty
            }
        } header: {
            HStack {
                if passports.passports.count > 1 { Text("Your passports") } else { Text("Your passport") }
                Spacer()
                if !passports.passports.isEmpty {
                    Button("Edit", action: onEdit)
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
        }
    }

    private var current: String? {
        if let shown, passports.contains(shown) { return shown }
        return passports.primary
    }

    /// Your other passports, in your order, under the full row.
    private var others: [String] {
        passports.passports.filter { $0 != current }
    }

    private func full(_ iso: String) -> some View {
        let rank = strength.rank(for: iso, countries: catalog.countries)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: iso, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog.name(forISO2: iso) ?? iso)
                        .typography(.h3)
                        .foregroundStyle(Theme.ink)
                    if passports.passports.count > 1 { position(iso) }
                }
                Spacer(minLength: Spacing.sm)
                MetricsInfoButton { onInfo(iso) }
                    .buttonStyle(.borderless)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.lg) { stats(rank) }
                VStack(alignment: .leading, spacing: Spacing.md) { stats(rank) }
            }
            .redacted(reason: rank == nil && !strength.loadFailed ? .placeholder : [])

            if rank == nil && strength.loadFailed {
                Text("Couldn't load the ranking. Pull to refresh later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xl) { links(iso) }
                VStack(alignment: .leading, spacing: Spacing.md) { links(iso) }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// A passport that isn't shown: flag, name, rank and visa-free count.
    private func compact(_ iso: String) -> some View {
        let rank = strength.rank(for: iso, countries: catalog.countries)
        return HStack(spacing: Spacing.md) {
            CountryFlag(iso2: iso, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(catalog.name(forISO2: iso) ?? iso)
                    .lineLimit(1)
                position(iso)
            }
            Spacer(minLength: Spacing.sm)
            if let rank {
                Text(verbatim: "#\(rank.rank) · ")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                + Text("\(rank.visaFree) visa-free")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// "Primary", "Second", …: on every row, so all rows of a kind are the
    /// same height.
    private func position(_ iso: String) -> some View {
        Text(verbatim: PassportPicking.tag(for: iso, in: passports.passports) ?? "")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func links(_ iso: String) -> some View {
        Button { onDetail(iso) } label: { linkLabel("Passport details") }
            .buttonStyle(.borderless)
        Button {
            explore.mode = .map
            tabs.selection = .explore
        } label: {
            linkLabel("See where you can go")
        }
        .buttonStyle(.borderless)
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
        // The numbers alone; what each one means is behind the ⓘ.
        PassportStat(label: "Rank", value: rank.map { "#\($0.rank)" } ?? "#00")
        PassportStat(label: "Visa-free", value: rank.map { "\($0.visaFree)" } ?? "000")
        PassportStat(label: "Mobility", value: rank.map { "\($0.mobilityScore)" } ?? "000")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pick your passport")
                .typography(.h3)
                .foregroundStyle(Theme.ink)
            Text("See its rank, where you can go visa-free, and what each trip needs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onEdit) {
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
}

// MARK: - Rule changes

/// The latest published rule changes for your passport (or all passports).
private struct RuleChangesSection: View {
    let model: RuleChangesModel
    let onOpen: () -> Void

    @Environment(CountryStore.self) private var catalog

    var body: some View {
        Section {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.md)
            } else if model.changes.isEmpty {
                Text(model.failed
                     ? "Couldn't load rule changes."
                     : "No published changes yet. New entries appear here as our team verifies them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.changes) { change in
                    Button(action: onOpen) { row(change) }
                        .foregroundStyle(Theme.ink)
                }
            }
        } header: {
            HStack {
                Text("Latest rule changes")
                Spacer()
                Button("See all", action: onOpen)
                    .font(.subheadline)
                    .textCase(nil)
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(change.localizedTitle())
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: Spacing.xs) {
                CountryFlag(iso2: change.destinationIso2, size: 16)
                Text(catalog.name(forISO2: change.destinationIso2) ?? change.destinationIso2)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Guides and tools

/// The web dashboard's "Guides and tools" (`GuidesGrid`), pointed at your own
/// passports and visas: compare, the passport index, a destination guide,
/// travel essentials, how we verify, and the blog. The passport screens open
/// natively; the rest open the website.
private struct GuidesSection: View {
    let onWeb: (String) -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog
    @Environment(TrackerStore.self) private var trackers
    @Environment(ExploreSelection.self) private var explore
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        let primary = passports.primary.flatMap { catalog.country($0) }
        let primaryName = passports.primary.map { catalog.name(forISO2: $0) ?? $0 }
        let secondName = passports.passports.dropFirst().first.map { catalog.name(forISO2: $0) ?? $0 }
        Section("Guides and tools") {
            NavigationLink(value: PassportRoute.compare(passports.passports)) {
                if let primaryName, let secondName {
                    RowLabel(icon: "rectangle.split.2x1", title: "Compare passports",
                             hint: "\(primaryName) vs \(secondName)")
                } else {
                    RowLabel(icon: "rectangle.split.2x1", title: "Compare passports",
                             hint: "Side by side, destination by destination")
                }
            }
            NavigationLink(value: PassportRoute.ranking) {
                RowLabel(icon: "globe", title: "Passport index",
                         hint: "Where every passport travels visa-free")
            }
            if let tracked = trackedDestination {
                NavigationLink(value: CatalogRoute.destination(tracked.iso2)) {
                    RowLabel(flag: tracked.iso2, title: "\(tracked.name) guide",
                             hint: "Visas, fees and official sources")
                }
            } else {
                Button {
                    explore.mode = .list
                    tabs.selection = .explore
                } label: {
                    RowLabel(icon: "map", title: "Destination guides",
                             hint: "Every country's visas and entry rules", chevron: true)
                }
                .foregroundStyle(Theme.ink)
            }
            Button {
                onWeb(primary?.slug.map { "/travel/\($0)" } ?? "/travel")
            } label: {
                if let primaryName {
                    RowLabel(icon: "suitcase", title: "Travel essentials",
                             hint: "For travellers from \(primaryName)", chevron: true)
                } else {
                    RowLabel(icon: "suitcase", title: "Travel essentials",
                             hint: "Insurance, eSIM and what to pack", chevron: true)
                }
            }
            .foregroundStyle(Theme.ink)
            Button { onWeb("/how-we-verify") } label: {
                RowLabel(icon: "checkmark.shield", title: "How we verify",
                         hint: "Our sources and how often we check them", chevron: true)
            }
            .foregroundStyle(Theme.ink)
            Button { onWeb("/blog") } label: {
                RowLabel(icon: "book.closed", title: "Blog",
                         hint: "Visa news and practical guides", chevron: true)
            }
            .foregroundStyle(Theme.ink)
        }
    }

    /// The most recent visa you're tracking (web: one guide card at most).
    private var trackedDestination: (iso2: String, name: String)? {
        guard let tracker = trackers.trackers.map(\.tracker).first(where: { !$0.isArchived }),
              let country = catalog.country(tracker.destinationIso2), country.slug != nil
        else { return nil }
        let iso = country.iso2.uppercased()
        return (iso, catalog.name(forISO2: iso) ?? country.name)
    }
}

// MARK: - Row

/// A settings-style row: icon (or flag), title, one line of help, and an
/// optional chevron for buttons (navigation links draw their own).
private struct RowLabel: View {
    var icon: String? = nil
    var flag: String? = nil
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    var chevron = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Group {
                if let flag {
                    CountryFlag(iso2: flag, size: 24)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

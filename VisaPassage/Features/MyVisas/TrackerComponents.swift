import SwiftUI

// Tracker building blocks shared by My visas, the tracker screens and the Home
// dashboard. Ports of `MyVisasWidget`, `HistoryList` and `SubmissionActions`
// in `web/src/app/[locale]/(app)/app/_components/`.

/// Typed navigation for the tracker screens (`/app/trackers/{id}` and
/// `/app/trackers/{id}/complete`).
enum TrackerRoute: Hashable {
    case detail(UUID)
    case complete(UUID)
}

extension View {
    /// Registers the tracker screens on the enclosing `NavigationStack`.
    func trackerDestinations() -> some View {
        navigationDestination(for: TrackerRoute.self) { route in
            switch route {
            case let .detail(id): TrackerDetailView(trackerID: id)
            case let .complete(id): TrackerCompletionView(trackerID: id)
            }
        }
    }
}

/// A status pill: the tracker status in its tone, or neutral (`StatusBadge`).
struct TrackerStatusBadge: View {
    let text: String
    let hue: StatusHue?

    var body: some View {
        if let hue {
            StatusBadge(text: text, hue: hue)
        } else {
            NeutralBadge(text: text)
        }
    }
}

/// A thin progress bar (`h-1` / `h-1.5`, ink on surface-2).
struct TrackerProgressBar: View {
    let ratio: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule().fill(Theme.ink).frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: ratio)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((ratio * 100).rounded()))%"))
    }
}

/// Eyebrow-style section label (11pt uppercase, tracking 0.14em, ink-soft).
struct DashEyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.custom("Geist-Medium", size: 11))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - Visa cards

/// "Your other visas" / "In progress" (`MyVisasWidget`): a title with a count,
/// then one card per tracker.
struct MyVisasSection: View {
    let title: String
    let trackers: [TrackerSummary]

    var body: some View {
        if !trackers.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.custom("Geist-Medium", size: 17))
                        .tracking(-0.17)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(verbatim: "\(trackers.count)")
                        .font(Typography.font(.monoSm))
                        .foregroundStyle(Theme.textSoft)
                }
                ForEach(trackers) { tracker in
                    NavigationLink(value: TrackerRoute.detail(tracker.id)) {
                        VisaCard(summary: tracker)
                    }
                    .buttonStyle(PressShrinkStyle())
                }
            }
        }
    }
}

/// One tracker as a card (`VisaCard`): flag, title, route, stage badge, progress.
struct VisaCard: View {
    let summary: TrackerSummary
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        let t = summary.tracker
        let progress = summary.progress
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                CountryFlag(iso2: t.destinationIso2, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(.custom("Geist-Medium", size: 15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(routeLine(t))
                        .font(.custom("Geist-Regular", size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if t.status.stage == .decision {
                    TrackerStatusBadge(text: t.status.label, hue: t.status.hue)
                } else {
                    NeutralBadge(text: t.status.stage.label)
                }
            }
            VStack(spacing: Spacing.sm) {
                HStack {
                    Text("\(progress.done) of \(progress.total) documents")
                        .font(.custom("GeistMono-Regular", size: 12))
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text(verbatim: "\(progress.percent)%")
                        .font(.custom("GeistMono-Regular", size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                TrackerProgressBar(ratio: progress.ratio)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
        )
    }

    private func routeLine(_ t: Tracker) -> String {
        let country = catalog.name(forISO2: t.destinationIso2) ?? t.destinationIso2
        if let traveller = t.travellerName, !traveller.isEmpty { return "\(country) · \(traveller)" }
        return country
    }
}

// MARK: - History

/// Decided or archived visas, newest first (`HistoryList`). `limit` caps the
/// rows (the dashboard shows 3) and adds "See all".
struct TrackerHistoryList: View {
    let trackers: [TrackerSummary]
    var limit: Int? = nil
    var onSeeAll: (() -> Void)? = nil

    @Environment(CountryStore.self) private var catalog

    var body: some View {
        if !trackers.isEmpty {
            let shown = limit.map { Array(trackers.prefix($0)) } ?? trackers
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .font(.custom("Geist-Medium", size: 17))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let limit, trackers.count > limit, let onSeeAll {
                        Button(String(localized: "See all (\(trackers.count))"), action: onSeeAll)
                            .font(.custom("Geist-Medium", size: 13))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 { Divider().overlay(Theme.border) }
                        NavigationLink(value: TrackerRoute.detail(summary.id)) { row(summary.tracker) }
                            .buttonStyle(.plain)
                    }
                }
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: Hairline.width)
                )
            }
        }
    }

    private func row(_ t: Tracker) -> some View {
        HStack(spacing: Spacing.md) {
            CountryFlag(iso2: t.destinationIso2, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title)
                    .font(.custom("Geist-Medium", size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subline(t))
                    .font(.custom("Geist-Regular", size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 4) {
                TrackerStatusBadge(text: t.status.label, hue: t.status.hue)
                if t.isArchived {
                    Text("Archived")
                        .font(.custom("Geist-Regular", size: 11.5))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func subline(_ t: Tracker) -> String {
        let country = catalog.name(forISO2: t.destinationIso2) ?? t.destinationIso2
        let date = DashboardState.parseTimestamp(t.updatedAt)?
            .formatted(.dateTime.day().month(.abbreviated).year()) ?? ""
        return date.isEmpty ? country : "\(country) · \(date)"
    }
}

// MARK: - Submission actions

/// The submission tools (`SubmissionActions`): a horizontal row of tiles —
/// checklist, nearest embassy (Maps), official site, destination guide,
/// timeline. External ones open outside the app.
struct SubmissionActions: View {
    let tracker: Tracker
    let progress: TrackerProgress
    let officialURL: String?
    /// The tracker screen scrolls instead of navigating.
    var onChecklist: (() -> Void)? = nil
    var onTimeline: (() -> Void)? = nil

    @Environment(CountryStore.self) private var catalog
    @Environment(\.openURL) private var openURL

    var body: some View {
        let destinationName = catalog.name(forISO2: tracker.destinationIso2) ?? tracker.destinationIso2
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                tile(icon: "checklist", accent: MapPalette.focus,
                     title: String(localized: "Checklist"),
                     hint: String(localized: "\(progress.done) of \(progress.total) done"), external: false) {
                    if let onChecklist { onChecklist() }
                }
                .modifier(LinkIfNeeded(route: onChecklist == nil ? TrackerRoute.detail(tracker.id) : nil))

                tile(icon: "building.columns", accent: RoutePalette.accent(.family),
                     title: String(localized: "Nearest embassy"),
                     hint: String(localized: "Open in Maps"), external: true) {
                    if let url = Self.embassyURL(destinationName) { openURL(url) }
                }

                if let officialURL, let url = URL(string: officialURL) {
                    tile(icon: "globe", accent: RoutePalette.accent(.immigrate),
                         title: String(localized: "Official site"),
                         hint: String(localized: "The authority's page"), external: true) {
                        openURL(url)
                    }
                }

                NavigationLink(value: guideRoute) {
                    tileLabel(icon: "book", accent: RoutePalette.accent(.study),
                              title: String(localized: "Destination guide"),
                              hint: String(localized: "Rules, fees and FAQ"), external: false)
                }
                .buttonStyle(PressShrinkStyle())

                tile(icon: "clock.arrow.circlepath", accent: RoutePalette.accent(.work),
                     title: String(localized: "Timeline"),
                     hint: String(localized: "Every status change"), external: false) {
                    if let onTimeline { onTimeline() }
                }
                .modifier(LinkIfNeeded(route: onTimeline == nil ? TrackerRoute.detail(tracker.id) : nil))
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.horizontal, -Spacing.xl)
        .accessibilityLabel(Text("Submission tools"))
    }

    /// The passport → destination corridor, else the destination guide (`pairHref`).
    private var guideRoute: CatalogRoute {
        if let passport = tracker.passportIso2, passport != tracker.destinationIso2 {
            return .corridor(from: passport, to: tracker.destinationIso2)
        }
        return .destination(tracker.destinationIso2)
    }

    /// `embassySearchUrl` (`web/src/lib/trackers/embassy.ts`).
    static func embassyURL(_ destinationName: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/search/")
        c?.queryItems = [.init(name: "api", value: "1"),
                         .init(name: "query", value: "Embassy of \(destinationName) near me")]
        return c?.url
    }

    private func tile(icon: String, accent: Color, title: String, hint: String, external: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileLabel(icon: icon, accent: accent, title: title, hint: hint, external: external)
        }
        .buttonStyle(PressShrinkStyle())
    }

    private func tileLabel(icon: String, accent: Color, title: String, hint: String, external: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(title).font(.custom("Geist-Medium", size: 13.5)).foregroundStyle(Theme.ink)
                    if external {
                        Text(verbatim: "↗").font(.custom("Geist-Regular", size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text(hint).font(.custom("Geist-Regular", size: 12)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .frame(width: 188, alignment: .leading)
        .frame(minHeight: 56)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// Wraps a tile in a NavigationLink when it should navigate instead of act.
private struct LinkIfNeeded: ViewModifier {
    let route: TrackerRoute?
    func body(content: Content) -> some View {
        if let route {
            NavigationLink(value: route) { content.allowsHitTesting(false) }
                .buttonStyle(PressShrinkStyle())
        } else {
            content
        }
    }
}

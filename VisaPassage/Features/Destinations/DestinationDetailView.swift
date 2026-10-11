import SwiftUI

/// Everything about one destination, matching `/destinations/[slug]`: every
/// purpose group and route into the country, personalised for the selected
/// passports. Short-stay access per passport links to its corridor; each
/// product opens the visa product screen.
struct DestinationDetailView: View {
    let destinationISO2: String

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    @State private var view: DestinationRoutesView?
    @State private var loading = true
    @State private var failed = false

    private let repo = CorridorRepository()

    private var country: Country? { catalog.country(destinationISO2) }
    private var iso2: String { destinationISO2.uppercased() }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header
                    if passports.passports.isEmpty {
                        CatalogStateCard(kind: .empty, message: String(localized: "Pick your passport to see the routes into this country."))
                    } else if let view {
                        access(view)
                        purposeChips(view, proxy: proxy)
                        ForEach(groups(view)) { group in
                            section(group, in: view).id(group.group)
                        }
                    } else if failed {
                        CatalogStateCard(kind: .failed) { Task { await load() } }
                    } else if loading {
                        CatalogStateCard(kind: .loading)
                    }
                    AdvisoryDisclaimer(text: "Typical eligibility from our visa data. No approval guarantees — official decisions prevail.")
                }
                .padding(Spacing.xl)
            }
        }
        .background(Theme.bg)
        .navigationTitle(country?.displayName ?? iso2)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let slug = country?.slug {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: AppLocale.current.webURL(path: "/destinations/\(slug)")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share"))
                }
            }
        }
        .task(id: passports.passports) { await load() }
    }

    // MARK: Header

    private var header: some View {
        let name = country?.displayName ?? iso2
        let count = view?.productRoutes.count ?? 0
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                CountryFlag(iso2: iso2, size: 44)
                Spacer()
            }
            Eyebrow(verbatim: country?.region ?? String(localized: "Destination"))
            Text("Every way into \(name).")
                .typography(.h1)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if view != nil {
                Text(verbatim: count > 0
                     ? String(localized: "\(count) verified routes across visit, study, work, investment, family and more.")
                     : String(localized: "Route research for this country is in progress."))
                    .typography(.bodyLg)
                    .foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Short-stay access

    private func access(_ view: DestinationRoutesView) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: "Your short-stay access")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(passports.passports.enumerated()), id: \.element) { index, passport in
                        if index > 0 { RowDivider(inset: 56) }
                        let status = view.visitorStatuses.first { $0.passportIso2.uppercased() == passport }
                        NavigationLink(value: CatalogRoute.corridor(from: passport, to: iso2)) {
                            HStack(spacing: Spacing.md) {
                                CountryFlag(iso2: passport, size: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: catalog.name(forISO2: passport) ?? passport)
                                        .typography(.sm).foregroundStyle(Theme.ink)
                                    if let status {
                                        HStack(spacing: Spacing.sm) {
                                            StatusBadge(text: status.status.label, hue: status.status.hue)
                                            if let days = status.daysAllowed {
                                                Text(verbatim: CorridorText.upToDaysCapitalized(days))
                                                    .typography(.xs).foregroundStyle(Theme.textBody)
                                            }
                                        }
                                    } else {
                                        Text("No short-stay data yet").typography(.xs).foregroundStyle(Theme.textSoft)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Purposes

    private func groups(_ view: DestinationRoutesView) -> [RouteGroup] {
        view.groups.filter { $0.group != .unknown && !$0.routes.isEmpty }
    }

    private func purposeChips(_ view: DestinationRoutesView, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(groups(view).filter { !$0.products.isEmpty }) { group in
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(group.group, anchor: .top) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: group.group.symbol).font(.system(size: 12))
                            Text(verbatim: group.group.label).font(.custom("Geist-Medium", size: 13))
                            Text(verbatim: "\(group.products.count)").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    }
                    .buttonStyle(PressShrinkStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Spacing.xl)
        .contentMargins(.horizontal, Spacing.xl, for: .scrollContent)
    }

    // MARK: Group sections

    private func section(_ group: RouteGroup, in view: DestinationRoutesView) -> some View {
        let available = group.routes.filter { $0.availability?.isAvailable == true }
        let unavailable = group.routes.compactMap { route -> String? in
            guard let a = route.availability, !a.isAvailable else { return nil }
            return a.programName ?? route.visaType.name
        }
        let unresearched = group.routes.filter { $0.tier == .unknown }.map(\.visaType.name)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: group.group.symbol).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Text(verbatim: group.group.label).typography(.h3).foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: group.products.isEmpty ? String(localized: "No verified routes yet") : CorridorText.routes(group.products.count))
                    .font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
            }
            ForEach(group.routes.filter { $0.product != nil }) { route in
                NavigationLink(value: CatalogRoute.product(context(route, in: view))) {
                    ProductRouteCard(route: route, eligibility: view.eligibility(for: route.product!.id).filter(\.isAssessed))
                }
                .buttonStyle(PressShrinkStyle())
            }
            if !available.isEmpty {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(available.enumerated()), id: \.element.id) { index, route in
                            if index > 0 { RowDivider() }
                            CatalogRow(title: route.availability?.programName ?? route.visaType.name,
                                       subtitle: route.availability?.summary,
                                       trailing: String(localized: "Available"), showsChevron: false) { EmptyView() }
                        }
                    }
                }
            }
            if !unavailable.isEmpty {
                Text("Not offered: \(unavailable.joined(separator: ", "))")
                    .typography(.xs).foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !unresearched.isEmpty {
                Text("Not yet researched: \(unresearched.joined(separator: ", "))")
                    .typography(.xs).foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func context(_ route: Route, in view: DestinationRoutesView) -> ProductContext {
        let product = route.product!
        let primary = passports.primary
        return ProductContext(
            product: product,
            visaTypeName: route.visaType.name,
            destination: country ?? view.country,
            passport: primary,
            passportStatus: route.passportStatus ?? view.visitorStatuses.first { $0.passportIso2.uppercased() == primary },
            eligibility: view.eligibility(for: product.id)
        )
    }

    // MARK: Data

    private func load() async {
        await catalog.loadIfNeeded()
        guard let slug = country?.slug, !passports.passports.isEmpty else {
            loading = false
            return
        }
        loading = true
        failed = false
        do {
            view = try await repo.destinationRoutes(slug: slug, passports: passports.passports) { fresh in
                await MainActor.run { view = fresh }
            }
        } catch {
            if view == nil { failed = true }
        }
        loading = false
    }
}

/// One product route: name, entry type, the passports' assessed eligibility,
/// summary, and fee / processing / stay.
private struct ProductRouteCard: View {
    let route: Route
    let eligibility: [RoutePassportEligibility]

    var body: some View {
        let product = route.product!
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(verbatim: route.visaType.name)
                        Text(verbatim: product.name)
                            .typography(.title)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                FlowLayout(spacing: 6) {
                    StatusBadge(text: ProductText.entryLabel(product.entryType), hue: .blue)
                    ForEach(eligibility, id: \.passportIso2) { row in
                        StatusBadge(text: "\(row.passportIso2) · \(ProductText.eligibilityLabel(row.eligibility))",
                                    hue: ProductText.eligibilityHue(row.eligibility))
                    }
                }
                if let summary = product.summary, !summary.isEmpty {
                    Text(verbatim: summary)
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: Spacing.lg) {
                    if let fee = Money.compact(cents: product.govFee, currency: product.currency) {
                        metric(.coin, fee)
                    }
                    if let days = product.processingDays { metric(.hourglass, CorridorText.approxDays(days)) }
                    if let stay = product.maxStayDays { metric(.calendar, CorridorText.days(stay)) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metric(_ icon: CatalogIcon, _ value: String) -> some View {
        HStack(spacing: 5) {
            CatalogGlyph(icon: icon, size: 15)
            Text(verbatim: value).font(Typography.font(.monoSm)).foregroundStyle(Theme.ink)
        }
    }
}

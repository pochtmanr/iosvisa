import StoreKit
import SwiftUI

/// The native `/travel/[from]/[to]`: everything about one route on one screen.
/// A dark hero in the welcome flow's language (the permanently dark band, the
/// glass answer card), then the landing's monochrome hairline sections.
struct CorridorView: View {
    @Environment(CountryStore.self) private var countries
    @Environment(RequirementsStore.self) private var requirements
    @Environment(PassportPreference.self) private var passports
    @Environment(AuthStore.self) private var auth
    @Environment(\.requestReview) private var requestReview

    @State private var model: CorridorModel
    @State private var catalog = DocumentCatalog()
    @State private var safari: SafariLink?
    @State private var showSignIn = false
    @State private var showComingSoon = false
    @State private var trackAfterSignIn = false

    private let toISO2: String

    init(fromISO2: String, toISO2: String) {
        self.toISO2 = toISO2.uppercased()
        _model = State(initialValue: CorridorModel(fromISO2: fromISO2, toISO2: toISO2))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                content
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xxxl)
            }
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.footerBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let corridor = model.corridor, let url = corridor.webURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareCardButton(url: url, renderID: "\(corridor.from.iso2)-\(corridor.to.iso2)-\(corridor.verdict.status.rawValue)") {
                        RouteShareCard(
                            fromISO2: corridor.from.iso2, fromName: corridor.from.displayName,
                            toISO2: corridor.to.iso2, toName: corridor.to.displayName,
                            status: corridor.verdict.status, daysAllowed: corridor.daysAllowed,
                            url: url
                        )
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { trackBar }
        .task(id: model.fromISO2) {
            await model.load(countries: countries, requirements: requirements)
            recordView()
            await catalog.load(passport: model.fromISO2)
        }
        .safariSheet($safari)
        .floatingSheet(isPresented: $showSignIn) { AuthSheet() }
        .floatingSheet(isPresented: $showComingSoon) {
            TrackComingSoonCard(webURL: trackerWebURL) { url in safari = SafariLink(url: url) }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, trackAfterSignIn else { return }
            trackAfterSignIn = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                showComingSoon = true
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let from = countries.country(model.fromISO2)
        let to = countries.country(toISO2)
        let fromName = from?.displayName ?? model.fromISO2
        let toName = to?.displayName ?? toISO2
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Eyebrow(text: "Travel corridor").foregroundStyle(.white.opacity(0.55))
                Spacer()
                passportSwitcher
            }
            RouteLine(fromISO2: model.fromISO2, toISO2: toISO2)
            (Text("\(toName) visa requirements").foregroundStyle(.white)
             + Text(verbatim: " ")
             + Text("for citizens of \(fromName).").foregroundStyle(.white.opacity(0.5)))
                .typography(.h1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            answerCard
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.footerBg
                // The landing hero's one radial wash, in the dark band.
                RadialGradient(colors: [.white.opacity(0.09), .clear], center: .top, startRadius: 0, endRadius: 360)
            }
            .padding(.top, -600) // bleed under the navigation bar on overscroll
        }
    }

    @ViewBuilder
    private var passportSwitcher: some View {
        if passports.passports.count > 1 {
            Menu {
                ForEach(passports.passports, id: \.self) { iso in
                    Button {
                        switchPassport(to: iso)
                    } label: {
                        Text(verbatim: countries.name(forISO2: iso) ?? iso)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    CountryFlag(iso2: model.fromISO2, size: 16)
                    Text("Passport").font(.custom("Geist-Medium", size: 12))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.14), in: Capsule())
            }
            .accessibilityLabel(Text("Change passport"))
        }
    }

    private func switchPassport(to iso: String) {
        guard iso.uppercased() != model.fromISO2 else { return }
        model = CorridorModel(fromISO2: iso, toISO2: toISO2)
    }

    @ViewBuilder
    private var answerCard: some View {
        switch model.state {
        case .loaded(let corridor):
            ShortStayAnswerCard(corridor: corridor)
        case .loading:
            ShortStayAnswerCard(corridor: nil)
                .redacted(reason: .placeholder)
        case .noAnswer, .failed:
            EmptyView()
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            CatalogStateCard(kind: .loading)
        case .failed:
            CatalogStateCard(kind: .failed) {
                Task { await model.load(countries: countries, requirements: requirements) }
            }
        case .noAnswer:
            VStack(alignment: .leading, spacing: Spacing.lg) {
                CatalogStateCard(kind: .empty, message: String(localized: "We have no short-stay answer for this route yet. Check the official source before you travel."))
                destinationHub
            }
        case .loaded(let corridor):
            CorridorSections(corridor: corridor, catalog: catalog, openURL: { safari = SafariLink(url: $0) })
        }
    }

    private var destinationHub: some View {
        let toName = countries.country(toISO2)?.displayName ?? toISO2
        return Card(padding: 0) {
            NavigationLink(value: CatalogRoute.destination(toISO2)) {
                CatalogRow(title: String(localized: "Every way into \(toName)"),
                           subtitle: String(localized: "The full destination guide — all purposes, fees and documents.")) {
                    CatalogGlyph(icon: .globe, size: 22)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Spotlight + the review counter, once the route has loaded.
    private func recordView() {
        guard let corridor = model.corridor, let url = corridor.webURL else { return }
        SpotlightIndexer.indexCorridor(
            from: corridor.from.iso2, fromName: corridor.from.displayName,
            to: corridor.to.iso2, toName: corridor.to.displayName,
            status: corridor.verdict.status.label, url: url
        )
        if ReviewPrompter().corridorViewed(from: corridor.from.iso2, to: corridor.to.iso2) {
            requestReview()
        }
    }

    // MARK: Track

    @ViewBuilder
    private var trackBar: some View {
        if let corridor = model.corridor, corridor.verdict.status != .noAdmission {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(height: Hairline.width)
                PrimaryButton(title: "Track this visa", icon: "plus") { track() }
                    .accessibilityIdentifier("track")
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
            }
            .background(Theme.bg.opacity(0.94))
            .background(.ultraThinMaterial)
        }
    }

    private func track() {
        if auth.isSignedIn {
            showComingSoon = true
        } else {
            trackAfterSignIn = true
            showSignIn = true
        }
    }

    /// The web tracker's deep link, which creates the same tracker there.
    private var trackerWebURL: URL? {
        guard let corridor = model.corridor else { return nil }
        var path = "/app/trackers/new?passport=\(corridor.from.iso2)&destination=\(corridor.to.iso2)"
        if let best = corridor.best { path += "&product=\(best.id.uuidString.lowercased())" }
        return AppLocale.current.webURL(path: path)
    }
}

// MARK: - Hero parts

/// Two passport-cover flags joined by a dashed flight line.
private struct RouteLine: View {
    let fromISO2: String
    let toISO2: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            CountryFlag(iso2: fromISO2, size: 40)
            ZStack {
                Line()
                    .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
                    .frame(height: 1)
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .background(Theme.footerBg)
            }
            CountryFlag(iso2: toISO2, size: 40)
        }
        .frame(maxWidth: 260)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: 0, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// The answer card in the welcome art's `StatusChip` style (paper on the dark
/// band, mono label over a hairline), carrying the
/// short-stay verdict. `nil` renders a placeholder for the redacted state.
private struct ShortStayAnswerCard: View {
    let corridor: Corridor?

    var body: some View {
        let status = corridor?.verdict.status ?? .visaFree
        let days = corridor?.daysAllowed
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text("Short-stay answer")
                    .font(.custom("GeistMono-Regular", size: 10.5))
                    .tracking(0.85)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
                UnverifiedChip()
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }

            VStack(alignment: .leading, spacing: Spacing.md) {
                StatusBadge(text: status.label, hue: status.hue)
                if status != .noAdmission {
                    if let days {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text("Up to").typography(.sm).foregroundStyle(Theme.textBody)
                            Text(verbatim: "\(days)")
                                .font(.custom("GeistMono-Medium", size: 40))
                                .tracking(-1)
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: CorridorText.days(days).replacingOccurrences(of: "\(days)", with: "").trimmingCharacters(in: .whitespaces))
                                .typography(.sm).foregroundStyle(Theme.ink)
                        }
                        Text(corridor?.tags.contains(.rule90180) == true ? "in any 180-day period" : "per visit")
                            .typography(.xs).foregroundStyle(Theme.textBody)
                    } else {
                        Text("No stay limit in our data").typography(.sm).foregroundStyle(Theme.textBody)
                    }
                }
                Text("From our visa matrix · not yet re-checked against an official source")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
        .padding(Spacing.lg)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: Hairline.width))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sections

private struct CorridorSections: View {
    let corridor: Corridor
    let catalog: DocumentCatalog
    let openURL: (URL) -> Void

    private static let previewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            summary
            checklist
            if !corridor.longStayGroups.isEmpty { beyond }
            faq
            sources
            hubs
            AdvisoryDisclaimer(text: "Typical eligibility from our visa data. No approval guarantees — official decisions prevail.")
        }
    }

    // Tags, key facts, the short-stay answer and the apply link.
    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if !corridor.tags.isEmpty {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(corridor.tags, id: \.self) { tag in
                        TagChip(text: label(for: tag), icon: icon(for: tag))
                    }
                }
            }
            FactGrid(items: corridor.facts.map { fact in
                FactItem(id: fact.kind.rawValue, icon: factIcon(fact.kind), label: fact.label, value: fact.value, hint: fact.hint)
            })
            Text(verbatim: corridor.shortStayAnswer)
                .typography(.bodyLg)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            // Matrix notes are English-only data, so the web shows them on `en` only.
            if AppLocale.current == .en, let notes = corridor.verdict.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(verbatim: notes).typography(.sm).foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = corridor.applyURL {
                ApplyOnlineButton { openURL(url) }
            }
        }
    }

    // MARK: Checklist

    @ViewBuilder
    private var checklist: some View {
        let docs = corridor.documents
        let notes = corridor.borderNotes
        if !docs.isEmpty || !notes.isEmpty || !corridor.visitorExtras.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let best = corridor.best, !docs.isEmpty {
                    SectionHeading(eyebrow: String(localized: "Before you go"),
                                   title: String(localized: "Documents for the \(best.name)"))
                    Text(verbatim: CorridorText.documentsInChecklist(docs.count))
                        .typography(.sm).foregroundStyle(Theme.textBody)
                    documentPreview(docs, product: best)
                } else if !notes.isEmpty {
                    SectionHeading(eyebrow: String(localized: "Before you go"),
                                   title: String(localized: "What to have ready"),
                                   muted: String(localized: "at the border."))
                    borderNotes(notes)
                }
                if !corridor.visitorExtras.isEmpty {
                    Eyebrow(text: "Other short-stay visas").padding(.top, Spacing.sm)
                    Card(padding: 0) {
                        productRows(corridor.visitorExtras, visaTypeName: VisaTypeGroup.visitor.label)
                    }
                }
            }
        }
    }

    private func documentPreview(_ docs: [DocumentRequirement], product: RouteProduct) -> some View {
        let context = productContext(product, visaTypeName: VisaTypeGroup.visitor.label)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(docs.prefix(Self.previewCount).enumerated()), id: \.element.id) { index, doc in
                    if index > 0 { RowDivider(inset: 52) }
                    DocumentRow(document: doc, hasGuide: catalog.guide(for: doc) != nil, passport: corridor.from.iso2)
                }
                RowDivider(inset: 0)
                NavigationLink(value: CatalogRoute.checklist(context)) {
                    HStack {
                        Text("See all \(docs.count) documents").typography(.sm).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func borderNotes(_ notes: [Corridor.BorderNote]) -> some View {
        VStack(spacing: Hairline.width) {
            ForEach(notes) { note in
                HStack(alignment: .top, spacing: Spacing.lg) {
                    CatalogGlyph(icon: noteIcon(note.kind), size: 28)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: note.title).typography(.body).fontWeight(.medium).foregroundStyle(Theme.ink)
                        Text(verbatim: note.body).typography(.sm).foregroundStyle(Theme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.lg)
                .background(Theme.bg)
            }
        }
        .background(Theme.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: Hairline.width))
    }

    // MARK: Beyond short stays

    private var beyond: some View {
        let toName = corridor.toProse
        let fromName = corridor.fromProse
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeading(eyebrow: String(localized: "Beyond short stays"),
                           title: String(localized: "Other ways into \(toName)"),
                           muted: String(localized: "for citizens of \(fromName)."))
            ForEach(corridor.longStayGroups) { group in
                RouteGroupCard(group: group, corridor: corridor, contextFor: { productContext($0, visaTypeName: $1) })
            }
        }
    }

    // MARK: FAQ

    private var faq: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeading(eyebrow: String(localized: "Questions"), title: String(localized: "Common questions"))
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(corridor.faq.enumerated()), id: \.element.id) { index, qa in
                        if index > 0 { RowDivider(inset: 0) }
                        FAQRow(qa: qa, startsOpen: index == 0)
                    }
                }
            }
        }
    }

    // MARK: Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeading(eyebrow: String(localized: "Sources"), title: String(localized: "How current is this"))
            Card {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Eyebrow(text: "Short-stay answer")
                            Spacer()
                            UnverifiedChip()
                        }
                        Text("This short-stay answer comes from our visa matrix and has not yet been re-checked against an official source. Confirm with the embassy or the official portal before you travel.")
                            .typography(.sm).foregroundStyle(Theme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let source = corridor.longStaySource {
                        Rectangle().fill(Theme.border).frame(height: Hairline.width)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Eyebrow(text: "Long-stay routes")
                            if let date = source.date {
                                Text("Last verified \(date)").typography(.sm).foregroundStyle(Theme.ink)
                                if let host = source.host {
                                    Text("Source: \(host)").font(Typography.font(.monoSm)).foregroundStyle(Theme.textBody)
                                }
                            } else {
                                Text("No official source on file yet").typography(.sm).foregroundStyle(Theme.textBody)
                            }
                        }
                    }
                    Button {
                        openURL(AppLocale.current.webURL(path: "/how-we-verify"))
                    } label: {
                        HStack(spacing: 4) {
                            Text("How we verify").typography(.sm)
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hubs: some View {
        let toName = corridor.to.displayName
        return Card(padding: 0) {
            NavigationLink(value: CatalogRoute.destination(corridor.to.iso2)) {
                CatalogRow(title: String(localized: "Every way into \(toName)"),
                           subtitle: String(localized: "The full destination guide — all purposes, fees and documents.")) {
                    CountryFlag(iso2: corridor.to.iso2, size: 28)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func productRows(_ products: [RouteProduct], visaTypeName: String?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                if index > 0 { RowDivider() }
                NavigationLink(value: CatalogRoute.product(productContext(product, visaTypeName: visaTypeName))) {
                    CatalogRow(title: product.name, subtitle: ProductText.feeLine(product)) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func productContext(_ product: RouteProduct, visaTypeName: String?) -> ProductContext {
        let route = corridor.routes.productRoutes.first { $0.product?.id == product.id }
        return ProductContext(
            product: product,
            visaTypeName: route?.visaType.name ?? visaTypeName,
            destination: corridor.to,
            passport: corridor.from.iso2,
            passportStatus: route?.passportStatus,
            eligibility: corridor.routes.eligibility(for: product.id)
        )
    }

    private func label(for tag: Corridor.Tag) -> String {
        switch tag {
        case .zone: return String(localized: "Schengen area")
        case .rule90180: return String(localized: "90/180-day rule")
        case .biometricPassport: return String(localized: "Biometric passport")
        case .etaPlanned(let product): return String(localized: "\(product) planned")
        case .applyOnline: return String(localized: "Apply online")
        case .applyConsulate: return String(localized: "Apply at a consulate")
        }
    }

    private func icon(for tag: Corridor.Tag) -> CatalogIcon {
        switch tag {
        case .zone: return .zone
        case .rule90180: return .calendar
        case .biometricPassport: return .passport
        case .etaPlanned: return .shieldClock
        case .applyOnline: return .globe
        case .applyConsulate: return .building
        }
    }

    private func factIcon(_ kind: Corridor.Fact.Kind) -> CatalogIcon {
        switch kind {
        case .stay: return .calendar
        case .fee: return .coin
        case .processing: return .hourglass
        case .validity: return .stamp
        case .routes: return .doc
        }
    }

    private func noteIcon(_ kind: Corridor.BorderNote.Kind) -> CatalogIcon {
        switch kind {
        case .biometric: return .passport
        case .rule: return .calendar
        case .eta: return .shieldClock
        case .border: return .info
        }
    }
}

/// One purpose group under "Beyond short stays": at most four routes, then a
/// link to the full destination guide and the types not offered.
private struct RouteGroupCard: View {
    let group: RouteGroup
    let corridor: Corridor
    let contextFor: (RouteProduct, String?) -> ProductContext

    private static let maxRows = 4

    var body: some View {
        let shown = group.routes.filter { $0.product != nil || $0.availability?.isAvailable == true }
        let unavailable = group.routes.compactMap { route -> String? in
            guard let availability = route.availability, !availability.isAvailable else { return nil }
            return availability.programName ?? route.visaType.name
        }
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: group.group.symbol).font(.system(size: 15)).foregroundStyle(Theme.ink)
                    Text(verbatim: group.group.label).typography(.title).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(verbatim: CorridorText.routes(group.products.count))
                        .font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                }
                .padding(Spacing.lg)
                ForEach(shown.prefix(Self.maxRows)) { route in
                    RowDivider(inset: 0)
                    row(route)
                }
                if shown.count > Self.maxRows {
                    RowDivider(inset: 0)
                    NavigationLink(value: CatalogRoute.destination(corridor.to.iso2)) {
                        HStack {
                            Text("+\(shown.count - Self.maxRows) more in the full guide").typography(.sm).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                        .padding(Spacing.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !unavailable.isEmpty {
                    RowDivider(inset: 0)
                    Text("Not offered: \(unavailable.joined(separator: ", "))")
                        .typography(.xs).foregroundStyle(Theme.textSoft)
                        .padding(Spacing.lg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ route: Route) -> some View {
        if let product = route.product {
            NavigationLink(value: CatalogRoute.product(contextFor(product, route.visaType.name))) {
                CatalogRow(title: product.name, subtitle: ProductText.feeLine(product)) { EmptyView() }
            }
            .buttonStyle(.plain)
        } else if let availability = route.availability {
            CatalogRow(title: availability.programName ?? route.visaType.name,
                       subtitle: String(localized: "Available"), showsChevron: false) { EmptyView() }
        }
    }
}

/// A question that expands in place; the first one starts open, as on the web.
private struct FAQRow: View {
    let qa: Corridor.QA
    @State private var open: Bool

    init(qa: Corridor.QA, startsOpen: Bool) {
        self.qa = qa
        _open = State(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Text(verbatim: qa.question).typography(.body).fontWeight(.medium).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if open {
                Text(verbatim: qa.answer).typography(.sm).foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(Spacing.lg)
    }
}

/// The track sheet until IOS-05 ships the native tracker.
private struct TrackComingSoonCard: View {
    let webURL: URL?
    let open: (URL) -> Void
    @Environment(\.dismissFloatingSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Visa tracker")
            Text("Tracking is coming to the app").typography(.h3).foregroundStyle(Theme.ink)
            Text("Keep your documents, appointment and decision dates in one place, with reminders before each deadline.")
                .typography(.body).foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Text("Until then, you can track this visa on visapassage.com with the same account.")
                .typography(.sm).foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.md) {
                if let webURL {
                    PrimaryButton(title: "Track on the web", icon: "arrow.up.right") {
                        dismiss()
                        open(webURL)
                    }
                }
                SecondaryButton(title: "Close") { dismiss() }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xl)
        .padding(.bottom, Spacing.md)
    }
}

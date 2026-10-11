import StoreKit
import SwiftUI

/// The native `/travel/[from]/[to]`: everything about one route on one screen.
/// On Home's grouped ground with its white cards: the route in the bar, then
/// the flags, the title, the short-stay answer card and the sections. "Track this visa" floats
/// over the content, with no bar behind it.
struct CorridorView: View {
    @Environment(CountryStore.self) private var countries
    @Environment(RequirementsStore.self) private var requirements
    @Environment(PassportPreference.self) private var passports
    @Environment(AuthStore.self) private var auth
    @Environment(TrackerStore.self) private var trackers
    @Environment(\.requestReview) private var requestReview

    @State private var model: CorridorModel
    @State private var catalog = DocumentCatalog()
    @State private var safari: SafariLink?
    @State private var showSignIn = false
    @State private var trackAfterSignIn = false
    @State private var creating = false
    @State private var trackError: String?
    /// The tracker to open after "Track this visa" (created or already there).
    @State private var openTracker: UUID?

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
        .background(Theme.groupedBg)
        .scrollIndicators(.hidden)
        .navigationTitle(routeTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .navigationDestination(item: $openTracker) { TrackerDetailView(trackerID: $0) }
        .alert(String(localized: "Couldn't save your changes. Please try again."),
               isPresented: Binding(get: { trackError != nil }, set: { if !$0 { trackError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(trackError ?? "")
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, trackAfterSignIn else { return }
            trackAfterSignIn = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                await createTracker()
            }
        }
    }

    // MARK: Hero

    /// The bar's title: the route, "Ukraine → Germany".
    private var routeTitle: String {
        let from = countries.country(model.fromISO2)?.displayName ?? model.fromISO2
        let to = countries.country(toISO2)?.displayName ?? toISO2
        return "\(from) → \(to)"
    }

    private var hero: some View {
        let toName = countries.country(toISO2)?.displayName ?? toISO2
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                RouteLine(fromISO2: model.fromISO2, toISO2: toISO2)
                Spacer()
                passportSwitcher
            }
            Text("\(toName) visa requirements")
                .foregroundStyle(Theme.ink)
                .typography(.h1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            answerCard
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.groupedCard, in: Capsule())
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
            // Floating: no bar or hairline behind it, a soft lift only.
            PrimaryButton(title: "Track this visa", icon: "plus", loading: creating) { track() }
                .accessibilityIdentifier("track")
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.sm)
        }
    }

    private func track() {
        if auth.isSignedIn {
            Task { await createTracker() }
        } else {
            trackAfterSignIn = true
            showSignIn = true
        }
    }

    /// `/app/trackers/new`: reuse the open tracker for this destination and
    /// visa, else create one with the visa's checklist, then open it.
    private func createTracker() async {
        guard let corridor = model.corridor, !creating else { return }
        creating = true
        defer { creating = false }
        let productID = corridor.best?.id
        do {
            if let existing = try await trackers.repo.existing(destination: corridor.to.iso2, productID: productID) {
                openTracker = existing
                return
            }
            let title = productID == nil
                ? String(localized: "Trip to \(countries.name(forISO2: corridor.to.iso2) ?? corridor.to.iso2)")
                : nil
            let id = try await trackers.repo.create(passport: corridor.from.iso2, destination: corridor.to.iso2,
                                                    productID: productID, title: title)
            await trackers.load()
            openTracker = id
        } catch let failure as TrackerRepository.Failure {
            trackError = failure.message
        } catch {
            trackError = TrackerRepository.Failure.saveFailed.message
        }
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
                    .stroke(Theme.inkSoft.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
                    .frame(height: 1)
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .background(Theme.groupedBg)
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

/// The answer card, a Home card (white on the grouped ground, no border or
/// shadow) with a mono label over a hairline, carrying the short-stay verdict. `nil` renders a placeholder for the redacted state.
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
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
                .background(Theme.groupedCard)
            }
        }
        .background(Theme.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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


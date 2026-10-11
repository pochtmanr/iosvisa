import SwiftUI

/// One visa product: eligibility, fees, processing, validity, how to apply and
/// the official link, its documents and where the data comes from. The web
/// shows the same content as a `RouteCard` on `/destinations/[slug]`.
struct VisaProductView: View {
    let context: ProductContext

    @State private var safari: SafariLink?

    private var product: RouteProduct { context.product }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                stats
                howToApply
                if !product.documents.isEmpty { documents }
                trust
                AdvisoryDisclaimer(text: "Typical eligibility from our visa data. No approval guarantees — official decisions prevail.")
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = context.webURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Share"))
                }
            }
        }
        .safariSheet($safari)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                CountryFlag(iso2: context.destination.iso2, size: 18)
                Eyebrow(verbatim: [context.destination.displayName, context.visaTypeName].compactMap { $0 }.joined(separator: " · "))
            }
            Text(verbatim: product.name)
                .typography(.h1)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: Spacing.sm) {
                StatusBadge(text: ProductText.entryLabel(product.entryType), hue: .blue)
                if let status = context.passportStatus, let passport = context.passport {
                    StatusBadge(text: "\(passport) · \(status.status.label)", hue: status.status.hue)
                }
                ForEach(assessed, id: \.passportIso2) { row in
                    StatusBadge(text: "\(row.passportIso2) · \(ProductText.eligibilityLabel(row.eligibility))",
                                hue: ProductText.eligibilityHue(row.eligibility))
                }
            }
            if let summary = product.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .typography(.bodyLg)
                    .foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let rights = ProductText.rights(product.attributes ?? [:])
            if !rights.isEmpty {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(rights, id: \.self) { TagChip(text: $0) }
                }
            }
            if let notes = eligibilityNotes {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    CatalogGlyph(icon: .info, size: 16)
                    Text(verbatim: notes).typography(.sm).foregroundStyle(Theme.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Only real assessments render as a verdict; the column default never does.
    private var assessed: [RoutePassportEligibility] {
        context.eligibility.filter(\.isAssessed)
    }

    private var eligibilityNotes: String? {
        let notes = assessed.compactMap(\.notes) + [product.eligibilityNotes].compactMap { $0 }
        let text = notes.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return product.eligibilityAssessed == true || !assessed.isEmpty ? text : nil
    }

    // MARK: Stats

    private var stats: some View {
        var items: [FactItem] = []
        let currency = product.currency
        if let fee = Money.compact(cents: product.govFee, currency: currency) {
            let indicative = product.govFeeIsIndicative == true
            items.append(FactItem(id: "gov", icon: .coin, label: String(localized: "Government fee"),
                                  value: indicative ? "≈ \(fee)" : fee,
                                  hint: indicative ? String(localized: "Indicative — varies by nationality") : nil))
        }
        if let fee = Money.compact(cents: product.serviceFee, currency: currency), (product.serviceFee ?? 0) > 0 {
            items.append(FactItem(id: "service", icon: .coin, label: String(localized: "Service fee"), value: fee, hint: nil))
        }
        if let days = product.processingDays {
            items.append(FactItem(id: "processing", icon: .hourglass, label: String(localized: "Processing"),
                                  value: CorridorText.approxDays(days), hint: String(localized: "typical")))
        }
        if let days = product.maxStayDays {
            items.append(FactItem(id: "stay", icon: .calendar, label: String(localized: "Max stay"),
                                  value: CorridorText.days(days), hint: nil))
        }
        if let days = product.validityDays {
            items.append(FactItem(id: "validity", icon: .stamp, label: String(localized: "Valid for"),
                                  value: CorridorText.days(days), hint: nil))
        }
        if let income = Money.compact(cents: product.minIncomeCents, currency: currency) {
            items.append(FactItem(id: "income", icon: .coin, label: String(localized: "Min. income / month"), value: income, hint: nil))
        }
        if let investment = Money.compact(cents: product.minInvestmentCents, currency: currency) {
            items.append(FactItem(id: "investment", icon: .coin, label: String(localized: "Min. investment"), value: investment, hint: nil))
        }
        return Group {
            if !items.isEmpty { FactGrid(items: items) }
        }
    }

    // MARK: How to apply

    private var howToApply: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeading(eyebrow: String(localized: "How to apply"), title: ProductText.howToApplyTitle(product.entryType))
            Text(verbatim: ProductText.howToApplyBody(product.entryType))
                .typography(.body)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
            if let url = product.officialURL {
                if product.entryType == .evisa || product.entryType == .eta {
                    ApplyOnlineButton { safari = SafariLink(url: url) }
                } else {
                    SecondaryButton(title: "Official information", icon: "arrow.up.right") { safari = SafariLink(url: url) }
                }
            }
        }
    }

    // MARK: Documents

    private var documents: some View {
        let docs = product.orderedDocuments
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeading(eyebrow: String(localized: "Documents"), title: String(localized: "What to have ready"))
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(docs.prefix(3).enumerated()), id: \.element.id) { index, doc in
                        if index > 0 { RowDivider(inset: 52) }
                        DocumentRow(document: doc, hasGuide: false, passport: context.passport)
                    }
                    RowDivider(inset: 0)
                    NavigationLink(value: CatalogRoute.checklist(context)) {
                        HStack {
                            Text("Document checklist (\(docs.count))").typography(.sm).foregroundStyle(Theme.ink)
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
    }

    // MARK: Trust

    @ViewBuilder
    private var trust: some View {
        let date = CorridorText.verifiedDate(product.lastVerifiedAt)
        let host = product.sourceURL.flatMap(URL.webLink)?.displayHost
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                if let date {
                    Text("Last verified \(date)").typography(.xs).foregroundStyle(Theme.textBody)
                } else {
                    Text("No official source on file yet").typography(.xs).foregroundStyle(Theme.textBody)
                }
                if let host {
                    Text("Source: \(host)").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                }
            }
            Spacer()
            if let confidence = CorridorText.confidence(product.confidence) {
                StatusBadge(text: confidence.label, hue: confidence.hue)
            }
        }
        .padding(.top, Spacing.sm)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
    }
}

/// Product phrasing shared by the corridor, destination and product screens.
enum ProductText {
    /// "€80 · ~15 days", or nil when neither is known.
    static func feeLine(_ product: RouteProduct) -> String? {
        let parts = [
            Money.compact(cents: product.govFee, currency: product.currency),
            product.processingDays.map(CorridorText.approxDays),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func entryLabel(_ entry: EntryType) -> String {
        switch entry {
        case .visaFree: return String(localized: "Visa-free")
        case .visaOnArrival: return String(localized: "Visa on arrival")
        case .evisa: return String(localized: "eVisa")
        case .eta: return String(localized: "eTA")
        case .consular: return String(localized: "Consular visa")
        case .unknown: return String(localized: "Visa")
        }
    }

    static func eligibilityLabel(_ eligibility: VisaEligibility) -> String {
        switch eligibility {
        case .eligible: return String(localized: "Eligible")
        case .conditional: return String(localized: "May be eligible")
        case .notEligible: return String(localized: "Not eligible")
        case .unknown: return String(localized: "Requires review")
        }
    }

    static func eligibilityHue(_ eligibility: VisaEligibility) -> StatusHue {
        switch eligibility {
        case .eligible: return .green
        case .conditional: return .yellow
        case .notEligible: return .red
        case .unknown: return .orange
        }
    }

    static func howToApplyTitle(_ entry: EntryType) -> String {
        switch entry {
        case .evisa, .eta: return String(localized: "Apply online")
        case .visaOnArrival: return String(localized: "On arrival")
        case .visaFree: return String(localized: "No application")
        default: return String(localized: "Apply at a consulate")
        }
    }

    static func howToApplyBody(_ entry: EntryType) -> String {
        switch entry {
        case .evisa, .eta:
            return String(localized: "Submitted online on the official site before you travel. Check the official requirements for your nationality before you pay.")
        case .visaOnArrival:
            return String(localized: "Issued at the border when you arrive. Conditions apply — review the official requirements before travel.")
        case .visaFree:
            return String(localized: "No visa to apply for. Show your passport at the border.")
        default:
            return String(localized: "Arranged before travel through the embassy, consulate or its visa centre. Book an appointment and bring the documents below.")
        }
    }

    /// Granted rights from `visa_products.attributes` (`parseRights` on the web).
    static func rights(_ attributes: [String: JSONValue]) -> [String] {
        func allowed(_ value: JSONValue) -> Bool {
            if case .bool(false) = value { return false }
            if case .object(let o) = value, case .bool(false)? = o["allowed"] { return false }
            return true
        }
        func number(_ value: JSONValue, _ key: String) -> Int? {
            if case .object(let o) = value, case .number(let n)? = o[key], n > 0 { return Int(n) }
            return nil
        }
        var chips: [String] = []
        if let work = attributes["work_rights"], allowed(work) {
            chips.append(number(work, "hours_per_week").map { String(localized: "Work \($0) h/wk") } ?? String(localized: "Work"))
        }
        if let study = attributes["study_rights"], allowed(study) {
            chips.append(String(localized: "Study"))
        }
        if let residency = attributes["path_to_residency"], allowed(residency) {
            chips.append(number(residency, "years").map { String(localized: "Residency after \($0) years") } ?? String(localized: "Path to residency"))
        }
        if let family = attributes["family_inclusion"], allowed(family) {
            chips.append(String(localized: "Family can join"))
        }
        return chips
    }
}

/// Wraps children onto new lines (chips, badges).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

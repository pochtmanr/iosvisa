import Foundation

/// One route (passport → destination) resolved the way `/travel/[from]/[to]`
/// resolves it. A Swift port of `loadPair` (`web/src/lib/travel/load-pair.ts`),
/// `deriveCorridorTags` (`corridor-tags.ts`), `buildPairFaq` (`faq.ts`) and the
/// facts and border notes on the page. Pure: no network, no SwiftUI.
struct Corridor: Sendable, Hashable {
    let from: Country
    let to: Country
    /// The legacy matrix verdict. Always labelled "Unverified".
    let verdict: VisaRequirement
    let routes: DestinationRoutesView
    var locale: AppLocale = .current

    // MARK: Products

    /// Every visitor-group product.
    var visitorProducts: [RouteProduct] {
        routes.group(.visitor)?.routes.compactMap(\.product) ?? []
    }

    /// The product the short-stay verdict applies through: eVisa → evisa,
    /// eTA → eta, visa required → consular. Lowest `sort_order` wins.
    var best: RouteProduct? {
        let wanted: [EntryType]
        switch verdict.status {
        case .evisa: wanted = [.evisa]
        case .eta: wanted = [.eta]
        case .visaRequired: wanted = [.consular]
        default: return nil
        }
        return visitorProducts
            .filter { wanted.contains($0.entryType) }
            .min { $0.sortOrder < $1.sortOrder }
    }

    /// A planned travel authorisation (ETIAS …) for a visa-free passport.
    var etaProduct: RouteProduct? {
        guard verdict.status == .visaFree else { return nil }
        return visitorProducts.first { $0.entryType == .eta }
    }

    /// Other short-stay visas, only when the short stay itself needs one.
    var visitorExtras: [RouteProduct] {
        guard let best else { return [] }
        return visitorProducts.filter { $0.id != best.id && $0.entryType != .eta }
    }

    /// The matrix often lacks days for visa-required corridors; the product's
    /// own max stay (Schengen C: 90) fills the gap.
    var daysAllowed: Int? { verdict.daysAllowed ?? best?.maxStayDays }

    /// Non-visitor groups that have at least one route.
    var longStayGroups: [RouteGroup] {
        routes.groups.filter { $0.group != .visitor && $0.group != .unknown && $0.routes.contains { $0.tier != .unknown } }
    }

    var longStayProducts: [RouteProduct] { longStayGroups.flatMap(\.products) }

    /// The application statuses (`canApply` on the web).
    var canApply: Bool { [.evisa, .eta, .visaRequired].contains(verdict.status) }

    /// The best product's checklist, in catalog order.
    var documents: [DocumentRequirement] {
        guard canApply, let best else { return [] }
        return best.orderedDocuments
    }

    /// The destination's zones. The web reads `visa_zone_members`; the zone a
    /// product is filed under is the same signal without another query.
    var zoneCodes: [String] {
        Array(Set(routes.productRoutes.compactMap { $0.product?.zoneCode })).sorted()
    }

    var inSchengen: Bool { zoneCodes.contains("schengen") }

    /// The official site the "Apply online" pill opens (eVisa / eTA only).
    var applyURL: URL? {
        guard tags.contains(.applyOnline), let raw = best?.sourceURL else { return nil }
        return URL.webLink(raw)
    }

    // MARK: Tags

    enum Tag: Hashable, Sendable {
        case zone(String)
        case rule90180
        case biometricPassport
        case etaPlanned(String)
        case applyOnline
        case applyConsulate
    }

    var tags: [Tag] {
        var tags: [Tag] = []
        let zone = zoneCodes.first { $0 == "schengen" }
        if let zone { tags.append(.zone(zone)) }
        if zone == "schengen", daysAllowed == 90, verdict.status == .visaFree || verdict.status == .eta {
            tags.append(.rule90180)
        }
        if verdict.notes?.range(of: "biometric", options: .caseInsensitive) != nil {
            tags.append(.biometricPassport)
        }
        if let etaProduct { tags.append(.etaPlanned(etaProduct.name)) }
        switch best?.entryType {
        case .evisa, .eta: tags.append(.applyOnline)
        case .consular: tags.append(.applyConsulate)
        default: break
        }
        return Array(tags.prefix(5))
    }

    // MARK: Facts

    struct Fact: Hashable, Sendable, Identifiable {
        enum Kind: String, Sendable { case stay, fee, processing, validity, routes }
        let kind: Kind
        let label: String
        let value: String?
        let hint: String?
        var id: Kind { kind }
    }

    var facts: [Fact] {
        let status = verdict.status
        let hasDays = daysAllowed != nil && status != .noAdmission
        var facts: [Fact] = [
            Fact(
                kind: .stay,
                label: String(localized: "Max stay"),
                value: hasDays ? CorridorText.days(daysAllowed!) : nil,
                hint: hasDays
                    ? (tags.contains(.rule90180) ? String(localized: "in any 180 days") : String(localized: "per visit"))
                    : String(localized: "Not in our data")
            ),
        ]
        if status == .visaFree {
            facts.append(Fact(kind: .fee, label: String(localized: "Government fee"),
                              value: String(localized: "None"), hint: String(localized: "No visa for a short stay")))
            facts.append(Fact(kind: .processing, label: String(localized: "Processing"),
                              value: String(localized: "Not needed"), hint: String(localized: "Show your passport at the border")))
        } else {
            let fee = best.flatMap { Money.compact(cents: $0.govFee, currency: $0.currency, locale: locale) }
            facts.append(Fact(kind: .fee, label: String(localized: "Government fee"),
                              value: fee, hint: fee != nil ? best?.name : String(localized: "Not in our data")))
            let days = best?.processingDays
            facts.append(Fact(kind: .processing, label: String(localized: "Processing"),
                              value: days.map(CorridorText.approxDays),
                              hint: days != nil ? String(localized: "typical") : String(localized: "Not in our data")))
        }
        if let best, let validity = best.validityDays, validity > 0 {
            facts.append(Fact(kind: .validity, label: String(localized: "Valid for"),
                              value: CorridorText.days(validity), hint: best.name))
        } else {
            let count = longStayProducts.count
            facts.append(Fact(
                kind: .routes,
                label: String(localized: "Long-stay routes"),
                value: count > 0 ? CorridorText.routes(count) : String(localized: "None listed"),
                hint: count > 0 ? String(localized: "Study, work, family and more") : nil
            ))
        }
        return facts
    }

    // MARK: Border notes (visa-free corridors with no product checklist)

    struct BorderNote: Hashable, Sendable, Identifiable {
        enum Kind: String, Sendable { case biometric, rule, eta, border }
        let kind: Kind
        let title: String
        let body: String
        var id: Kind { kind }
    }

    var borderNotes: [BorderNote] {
        guard documents.isEmpty else { return [] }
        var notes: [BorderNote] = []
        if tags.contains(.biometricPassport) {
            notes.append(BorderNote(kind: .biometric, title: String(localized: "A biometric passport"),
                                    body: String(localized: "Our record for this corridor notes visa-free entry with a biometric (chip) passport.")))
        }
        if tags.contains(.rule90180) {
            notes.append(BorderNote(kind: .rule, title: String(localized: "Your day count"),
                                    body: String(localized: "Visa-free days across the whole Schengen area count together: at most 90 days in any rolling 180-day period.")))
        }
        if let etaProduct {
            notes.append(BorderNote(kind: .eta, title: String(localized: "\(etaProduct.name) is planned"),
                                    body: String(localized: "A travel authorisation is planned for this zone. It is not required today, and our data holds no confirmed start date.")))
        }
        if inSchengen, verdict.status == .visaFree || verdict.status == .eta {
            notes.append(BorderNote(kind: .border, title: String(localized: "Answers for the border check"),
                                    body: String(localized: "General Schengen entry conditions: officers may ask about the purpose of your trip, where you will stay and how you will cover your costs.")))
        }
        return notes
    }

    // MARK: Prose

    var fromProse: String { CorridorText.nameInProse(from.localizedName(in: locale), locale: locale) }
    var toProse: String { CorridorText.nameInProse(to.localizedName(in: locale), locale: locale) }

    /// The six-status short-stay answer (`faq.answer.{status}`).
    var shortStayAnswer: String {
        CorridorText.shortStayAnswer(status: verdict.status, from: fromProse, to: toProse,
                                     days: verdict.daysAllowed)
    }

    // MARK: FAQ

    struct QA: Hashable, Sendable, Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    var faq: [QA] {
        let status = verdict.status
        var qas = [QA(
            question: String(localized: "Do citizens of \(fromProse) need a visa to visit \(toProse)?"),
            answer: CorridorText.shortStayAnswer(status: status, from: fromProse, to: toProse, days: verdict.daysAllowed)
        )]
        if let days = verdict.daysAllowed, status != .noAdmission {
            let upTo = CorridorText.upToDaysCapitalized(days)
            let statusProse = status.label.lowercased()
            qas.append(QA(
                question: String(localized: "How long can citizens of \(fromProse) stay in \(toProse)?"),
                answer: String(localized: "\(upTo) per visit under the \(statusProse) arrangement, as of our last verification. Longer stays or other purposes use a dedicated visa route.")
            ))
        }
        if canApply, let best {
            let toName = to.localizedName(in: locale)
            var parts = [String(localized: "Through the \(best.name), submitted online or via the official channel before travel.")]
            if let fee = Money.compact(cents: best.govFee, currency: best.currency, locale: locale) {
                parts.append(String(localized: "The government fee is \(fee)."))
            }
            if let days = best.processingDays {
                parts.append(String(localized: "Processing typically takes \(days) days."))
            }
            if let date = CorridorText.verifiedDate(best.lastVerifiedAt, locale: locale) {
                parts.append(String(localized: "Requirements can vary by nationality and change over time — last verified \(date)."))
            } else {
                parts.append(String(localized: "Requirements can vary by nationality and change over time."))
            }
            let question: String
            switch status {
            case .evisa: question = String(localized: "How do citizens of \(fromProse) apply for the \(toName) eVisa?")
            case .eta: question = String(localized: "How do citizens of \(fromProse) apply for the \(toName) eTA?")
            default: question = String(localized: "How do citizens of \(fromProse) apply for the \(toName) visa?")
            }
            qas.append(QA(question: question, answer: parts.joined(separator: " ")))
        }
        let verified = longStayProducts.count
        if verified > 0 {
            let toName = to.localizedName(in: locale)
            let toCap = toProse.prefix(1).uppercased() + toProse.dropFirst()
            let routes = CorridorText.verifiedRoutes(verified)
            qas.append(QA(
                question: String(localized: "Can citizens of \(fromProse) work or study in \(toProse)?"),
                answer: String(localized: "\(toCap) has \(routes) across work, study, residence and other purposes. Eligibility varies by route and nationality — see the full \(toName) visa guide for details.")
            ))
        }
        return Array(qas.prefix(4))
    }

    // MARK: Sources

    /// The newest verified long-stay product: its date and source host.
    var longStaySource: (date: String?, host: String?)? {
        let products = longStayProducts
        guard !products.isEmpty else { return nil }
        let newest = products
            .filter { $0.lastVerifiedAt != nil }
            .max { ($0.lastVerifiedAt ?? "") < ($1.lastVerifiedAt ?? "") }
        return (
            CorridorText.verifiedDate(newest?.lastVerifiedAt, locale: locale),
            newest?.sourceURL.flatMap(URL.webLink)?.displayHost
        )
    }

    /// `/travel/{from}/{to}` on the web, in the app's locale.
    var webURL: URL? {
        guard let fromSlug = from.slug, let toSlug = to.slug else { return nil }
        return locale.webURL(path: "/travel/\(fromSlug)/\(toSlug)")
    }
}

// MARK: - Copy helpers

/// Locale-aware phrasing shared by the catalog screens, mirroring the web's
/// `corridor` and `marketing.destinationDetail` messages.
enum CorridorText {
    static func days(_ n: Int) -> String { String(localized: "\(n) days") }
    static func approxDays(_ n: Int) -> String { String(localized: "~\(n) days") }
    static func routes(_ n: Int) -> String { String(localized: "\(n) routes") }
    static func verifiedRoutes(_ n: Int) -> String { String(localized: "\(n) verified routes") }
    static func documentsInChecklist(_ n: Int) -> String { String(localized: "\(n) documents in our checklist for this route.") }
    static func upToDays(_ n: Int) -> String { String(localized: "up to \(n) days") }
    static func upToDaysCapitalized(_ n: Int) -> String { String(localized: "Up to \(n) days") }

    /// "United States" → "the United States" in English sentences.
    static func nameInProse(_ name: String, locale: AppLocale) -> String {
        guard locale == .en else { return name }
        let articled: Set<String> = [
            "United States", "United Kingdom", "United Arab Emirates", "Netherlands", "Philippines", "Czech Republic",
        ]
        return articled.contains(name) ? "the \(name)" : name
    }

    static func shortStayAnswer(status: VisaStatus, from: String, to: String, days: Int?) -> String {
        let upTo = days.map(upToDays)
        switch status {
        case .visaFree:
            if let upTo {
                return String(localized: "No — citizens of \(from) can typically visit \(to) visa-free for stays of \(upTo). Longer stays or other purposes (work, study, residence) use a dedicated visa route.")
            }
            return String(localized: "No — citizens of \(from) can typically visit \(to) visa-free. Longer stays or other purposes (work, study, residence) use a dedicated visa route.")
        case .visaOnArrival:
            if let upTo {
                return String(localized: "Citizens of \(from) can typically obtain a visa on arrival in \(to) for stays of \(upTo). Conditions apply — review the official requirements before travel.")
            }
            return String(localized: "Citizens of \(from) can typically obtain a visa on arrival in \(to). Conditions apply — review the official requirements before travel.")
        case .evisa:
            if let upTo {
                return String(localized: "Yes — citizens of \(from) typically need an eVisa for \(to), applied for online before travel; stays of \(upTo) are typically allowed.")
            }
            return String(localized: "Yes — citizens of \(from) typically need an eVisa for \(to), applied for online before travel.")
        case .eta:
            if let upTo {
                return String(localized: "No visa — but citizens of \(from) typically need an electronic travel authorisation (eTA) for \(to), applied for online before travel; stays of \(upTo) are typically allowed.")
            }
            return String(localized: "No visa — but citizens of \(from) typically need an electronic travel authorisation (eTA) for \(to), applied for online before travel.")
        case .visaRequired:
            return String(localized: "Yes — citizens of \(from) typically need a visa for \(to), arranged before travel through a consular application.")
        case .noAdmission:
            return String(localized: "Entry to \(to) is currently not permitted for citizens of \(from), as of our last verification.")
        case .unknown:
            return String(localized: "We have no short-stay answer for this route yet. Check the official source before you travel.")
        }
    }

    /// "2026-05-12T…" → "12 May 2026" (en) / "12 мая 2026 г." (ru).
    static func verifiedDate(_ iso: String?, locale: AppLocale = .current) -> String? {
        guard let iso, let date = parseDate(iso) else { return nil }
        return date.formatted(
            .dateTime.day().month(.abbreviated).year()
                .locale(Locale(identifier: locale == .en ? "en_GB" : "ru_RU"))
        )
    }

    static func parseDate(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return fractional.date(from: iso) ?? plain.date(from: iso)
    }

    /// `enums.confidence`.
    static func confidence(_ raw: String?) -> (label: String, hue: StatusHue)? {
        switch raw {
        case "high": return (String(localized: "High confidence"), .green)
        case "medium": return (String(localized: "Medium confidence"), .yellow)
        case "low": return (String(localized: "Low confidence"), .red)
        default: return nil
        }
    }
}

/// The web's `formatMoneyCompact`: "€70", "€70.50", nil when absent.
enum Money {
    static func compact(cents: Int?, currency: String?, locale: AppLocale = .current) -> String? {
        guard let cents else { return nil }
        let code = (currency?.isEmpty == false ? currency! : "EUR").uppercased()
        let amount = Double(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: locale == .en ? "en_US" : "ru_RU")
        formatter.currencyCode = code
        formatter.minimumFractionDigits = amount.rounded() == amount ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(code)"
    }
}

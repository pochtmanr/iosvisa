import Foundation

/// A row in the public `visa_products` catalog — a concrete visa/permit a
/// traveller can pursue for a destination (or a zone such as Schengen). Mirrors
/// the web `VisaProduct` type and the live table columns.
struct VisaProduct: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var code: String
    var destinationIso2: String?
    var zoneCode: String?
    var name: String
    var category: VisaCategory
    var entryType: EntryType
    var applicationMode: ApplicationMode
    var defaultEligibility: VisaEligibility
    var maxStayDays: Int?
    var validityDays: Int?
    var processingTimeDays: Int?
    var govFeeCents: Int?
    var serviceFeeCents: Int?
    var currency: String
    var summary: String?
    var moreInfoURL: String?
    var visaTypeCode: String?
    var sortOrder: Int
    var isActive: Bool
    var attributes: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id, code, name, category, currency, summary
        case destinationIso2 = "destination_iso2"
        case zoneCode = "zone_code"
        case entryType = "entry_type"
        case applicationMode = "application_mode"
        case defaultEligibility = "default_eligibility"
        case maxStayDays = "max_stay_days"
        case validityDays = "validity_days"
        case processingTimeDays = "processing_time_days"
        case govFeeCents = "gov_fee_cents"
        case serviceFeeCents = "service_fee_cents"
        case moreInfoURL = "more_info_url"
        case visaTypeCode = "visa_type_code"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case attributes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        destinationIso2 = try c.decodeIfPresent(String.self, forKey: .destinationIso2)
        zoneCode = try c.decodeIfPresent(String.self, forKey: .zoneCode)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(VisaCategory.self, forKey: .category)
        entryType = try c.decode(EntryType.self, forKey: .entryType)
        applicationMode = try c.decode(ApplicationMode.self, forKey: .applicationMode)
        defaultEligibility = try c.decode(VisaEligibility.self, forKey: .defaultEligibility)
        maxStayDays = try c.decodeIfPresent(Int.self, forKey: .maxStayDays)
        validityDays = try c.decodeIfPresent(Int.self, forKey: .validityDays)
        processingTimeDays = try c.decodeIfPresent(Int.self, forKey: .processingTimeDays)
        govFeeCents = try c.decodeIfPresent(Int.self, forKey: .govFeeCents)
        serviceFeeCents = try c.decodeIfPresent(Int.self, forKey: .serviceFeeCents)
        currency = (try c.decodeIfPresent(String.self, forKey: .currency)) ?? "USD"
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        moreInfoURL = try c.decodeIfPresent(String.self, forKey: .moreInfoURL)
        visaTypeCode = try c.decodeIfPresent(String.self, forKey: .visaTypeCode)
        sortOrder = (try c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        isActive = (try c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
        attributes = (try c.decodeIfPresent([String: JSONValue].self, forKey: .attributes)) ?? [:]
    }
}

/// Visa-product purpose category, used to group routes on the destination
/// detail screen. Unknown values decode to `.other` so new categories never
/// break parsing.
enum VisaCategory: String, Codable, Sendable, CaseIterable {
    case tourist, business, work, study, family, transit, medical, official, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisaCategory(rawValue: raw) ?? .other
    }

    /// Section heading used when grouping routes by purpose.
    var groupLabel: String {
        switch self {
        case .tourist: return String(localized: "Tourism")
        case .business: return String(localized: "Business")
        case .work: return String(localized: "Work")
        case .study: return String(localized: "Study")
        case .family: return String(localized: "Family")
        case .transit: return String(localized: "Transit")
        case .medical: return String(localized: "Medical")
        case .official: return String(localized: "Official")
        case .other: return String(localized: "Other")
        }
    }

    /// Display order for the grouped sections.
    var sortRank: Int {
        switch self {
        case .tourist: return 0
        case .business: return 1
        case .work: return 2
        case .study: return 3
        case .family: return 4
        case .transit: return 5
        case .medical: return 6
        case .official: return 7
        case .other: return 8
        }
    }
}

/// A `visa_products` row resolved against a specific passport: the base product
/// plus the effective eligibility/mode/fees after folding any sparse
/// `visa_product_eligibility` override. Port of the web `ResolvedVisaProduct`.
struct ResolvedVisaProduct: Identifiable, Sendable, Hashable {
    var product: VisaProduct
    var effectiveEligibility: VisaEligibility
    var effectiveApplicationMode: ApplicationMode
    var effectiveGovFeeCents: Int?
    var effectiveServiceFeeCents: Int?
    var effectiveProcessingTimeDays: Int?
    var eligibilityNotes: String?

    var id: UUID { product.id }

    /// Marketplace-era split: `.ours` products were submitted online by the
    /// service, everything else is lodged by the traveller. Not shown in the
    /// UI any more (the marketplace is frozen); kept for the resolver tests.
    enum Channel { case online, manual }
    var channel: Channel { effectiveApplicationMode == .ours ? .online : .manual }

    /// "$210" style fee string combining gov + service fees, or nil when no fee.
    var feeDisplay: String? {
        let gov = effectiveGovFeeCents ?? 0
        let service = effectiveServiceFeeCents ?? 0
        let total = gov + service
        guard total > 0 else { return nil }
        return CurrencyFormat.string(cents: total, currency: product.currency)
    }

    var processingDisplay: String? {
        guard let days = effectiveProcessingTimeDays, days > 0 else { return nil }
        return String(localized: "~\(days) days")
    }

    /// Fold a sparse `visa_product_eligibility` override onto a base product.
    /// The override (when present for this passport) wins for eligibility,
    /// application mode, fees, and processing; otherwise the product defaults
    /// apply. Pure — mirrors the web resolver and is unit-tested.
    static func resolve(_ product: VisaProduct, override: VisaProductEligibility?) -> ResolvedVisaProduct {
        ResolvedVisaProduct(
            product: product,
            effectiveEligibility: override?.eligibility ?? product.defaultEligibility,
            effectiveApplicationMode: override?.applicationMode ?? product.applicationMode,
            effectiveGovFeeCents: override?.govFeeCents ?? product.govFeeCents,
            effectiveServiceFeeCents: override?.serviceFeeCents ?? product.serviceFeeCents,
            effectiveProcessingTimeDays: override?.processingTimeDays ?? product.processingTimeDays,
            eligibilityNotes: override?.notes
        )
    }
}

/// Resolved visa options for a (passport → destination) pair. Return shape of
/// `VisaRepository.destinationOptions`.
struct DestinationVisaOptions: Sendable {
    var passportIso2: String
    var destinationIso2: String
    var products: [ResolvedVisaProduct]
}

/// A sparse per-nationality override in `visa_product_eligibility`.
struct VisaProductEligibility: Codable, Sendable, Hashable {
    var productID: UUID
    var passportIso2: String
    var eligibility: VisaEligibility
    var applicationMode: ApplicationMode?
    var notes: String?
    var govFeeCents: Int?
    var serviceFeeCents: Int?
    var processingTimeDays: Int?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case passportIso2 = "passport_iso2"
        case eligibility, notes
        case applicationMode = "application_mode"
        case govFeeCents = "gov_fee_cents"
        case serviceFeeCents = "service_fee_cents"
        case processingTimeDays = "processing_time_days"
    }
}

/// Minimal currency formatting for fee chips. Fees are stored in minor units.
enum CurrencyFormat {
    static func string(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }
}

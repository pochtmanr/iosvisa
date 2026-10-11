import Foundation

// The web's composed destination view, as `GET /api/destinations/{slug}?passports=&locale=`
// returns it (`DestinationRoutesView` in `web/src/lib/destinations/types.ts`). The
// server already resolves the locale, so names, summaries and document labels
// arrive translated: never re-translate them here.

/// The seven purpose groups, in the web's `VISA_TYPE_GROUPS` order.
enum VisaTypeGroup: String, Codable, CaseIterable, Sendable, Hashable {
    case visitor
    case study
    case remoteWork = "remote_work"
    case investment
    case lifestyle
    case familyOrigin = "family_origin"
    case special
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisaTypeGroup(rawValue: raw) ?? .unknown
    }

    /// `enums.visaTypeGroup.{group}.name`.
    var label: String {
        switch self {
        case .visitor: return String(localized: "Visit")
        case .study: return String(localized: "Study & Training")
        case .remoteWork: return String(localized: "Work & Self-Employment")
        case .investment: return String(localized: "Invest & Capital")
        case .lifestyle: return String(localized: "Retire & Lifestyle")
        case .familyOrigin: return String(localized: "Family & Origin")
        case .special: return String(localized: "Special Categories")
        case .unknown: return String(localized: "Other")
        }
    }

    /// The purpose glyph used on group headers.
    var symbol: String {
        switch self {
        case .visitor: return "airplane"
        case .study: return "graduationcap"
        case .remoteWork: return "briefcase"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .lifestyle: return "sun.max"
        case .familyOrigin: return "person.2"
        case .special: return "star"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct DestinationRoutesView: Codable, Sendable, Hashable {
    var country: Country
    var groups: [RouteGroup]
    var passports: [String]
    var productEligibility: [String: [RoutePassportEligibility]]
    var visitorStatuses: [VisitorStatus]

    /// Every product route, in group order.
    var productRoutes: [Route] { groups.flatMap(\.routes).filter { $0.product != nil } }

    func group(_ group: VisaTypeGroup) -> RouteGroup? { groups.first { $0.group == group } }

    func eligibility(for productID: UUID) -> [RoutePassportEligibility] {
        productEligibility[productID.uuidString.lowercased()] ?? []
    }
}

struct RouteGroup: Codable, Sendable, Hashable, Identifiable {
    var group: VisaTypeGroup
    var routes: [Route]

    var id: VisaTypeGroup { group }
    /// Product routes only (the "verified" count the web shows).
    var products: [RouteProduct] { routes.compactMap(\.product) }
}

/// One visa type in a group: a researched product, an availability note, or
/// a type nobody has researched yet.
struct Route: Codable, Sendable, Hashable, Identifiable {
    enum Tier: String, Codable, Sendable { case product, availability, unknown }

    var visaType: VisaTypeInfo
    var tier: Tier
    var product: RouteProduct?
    var availability: RouteAvailability?
    var passportStatus: VisitorStatus?

    var id: String { product.map { $0.id.uuidString } ?? "\(tier.rawValue)-\(visaType.code)" }
}

struct VisaTypeInfo: Codable, Sendable, Hashable {
    var code: String
    var typeGroup: VisaTypeGroup
    var name: String
    var description: String?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case code, name, description
        case typeGroup = "type_group"
        case sortOrder = "sort_order"
    }
}

/// `country_visa_availability`: a researched yes/no for a visa type with no product.
struct RouteAvailability: Codable, Sendable, Hashable {
    var visaTypeCode: String
    var status: String
    var programName: String?
    var summary: String?
    var moreInfoURL: String?
    var sourceURL: String?
    var lastVerifiedAt: String?
    var confidence: String?

    var isAvailable: Bool { status == "available" }

    enum CodingKeys: String, CodingKey {
        case status, summary, confidence
        case visaTypeCode = "visa_type_code"
        case programName = "program_name"
        case moreInfoURL = "more_info_url"
        case sourceURL = "source_url"
        case lastVerifiedAt = "last_verified_at"
    }
}

/// A `visa_products` row with the loader's per-passport resolution
/// (`ResolvedVisaProductIntel` on the web) and its document checklist.
struct RouteProduct: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var code: String
    var destinationIso2: String?
    var zoneCode: String?
    var name: String
    var entryType: EntryType
    var maxStayDays: Int?
    var validityDays: Int?
    var processingTimeDays: Int?
    var govFeeCents: Int?
    var serviceFeeCents: Int?
    var currency: String?
    var summary: String?
    var moreInfoURL: String?
    var sortOrder: Int
    var visaTypeCode: String?
    var minIncomeCents: Int?
    var minInvestmentCents: Int?
    var attributes: [String: JSONValue]?
    var sourceURL: String?
    var lastVerifiedAt: String?
    var confidence: String?
    var govFeeIsIndicative: Bool?
    var eligibility: VisaEligibility?
    var eligibilityAssessed: Bool?
    var eligibilityNotes: String?
    var effectiveGovFeeCents: Int?
    var effectiveServiceFeeCents: Int?
    var effectiveProcessingTimeDays: Int?
    var documents: [DocumentRequirement]

    /// The fee and processing the web shows: the per-passport override when one
    /// applies, else the product's own column.
    var govFee: Int? { effectiveGovFeeCents ?? govFeeCents }
    var serviceFee: Int? { effectiveServiceFeeCents ?? serviceFeeCents }
    var processingDays: Int? { effectiveProcessingTimeDays ?? processingTimeDays }

    /// The documents in catalog order, as the corridor and the checklist list them.
    var orderedDocuments: [DocumentRequirement] { documents.sorted { $0.sortOrder < $1.sortOrder } }

    /// The official page: `source_url` (what the web's "Apply online" uses),
    /// else `more_info_url`. Only http(s) links count.
    var officialURL: URL? {
        [sourceURL, moreInfoURL].lazy.compactMap { $0 }.compactMap(URL.webLink).first
    }

    enum CodingKeys: String, CodingKey {
        case id, code, name, currency, summary, attributes, confidence, eligibility, documents
        case destinationIso2 = "destination_iso2"
        case zoneCode = "zone_code"
        case entryType = "entry_type"
        case maxStayDays = "max_stay_days"
        case validityDays = "validity_days"
        case processingTimeDays = "processing_time_days"
        case govFeeCents = "gov_fee_cents"
        case serviceFeeCents = "service_fee_cents"
        case moreInfoURL = "more_info_url"
        case sortOrder = "sort_order"
        case visaTypeCode = "visa_type_code"
        case minIncomeCents = "min_income_cents"
        case minInvestmentCents = "min_investment_cents"
        case sourceURL = "source_url"
        case lastVerifiedAt = "last_verified_at"
        case govFeeIsIndicative = "gov_fee_is_indicative"
        case eligibilityAssessed = "eligibility_assessed"
        case eligibilityNotes = "eligibility_notes"
        case effectiveGovFeeCents = "effective_gov_fee_cents"
        case effectiveServiceFeeCents = "effective_service_fee_cents"
        case effectiveProcessingTimeDays = "effective_processing_time_days"
    }
}

/// One passport's eligibility for one product. Only `override` and
/// `pair_matrix` are assessments; `default` must never render as a verdict.
struct RoutePassportEligibility: Codable, Sendable, Hashable {
    var passportIso2: String
    var eligibility: VisaEligibility
    var notes: String?
    var source: String
    var reason: String?

    var isAssessed: Bool { source != "default" }

    enum CodingKeys: String, CodingKey {
        case eligibility, notes, source, reason
        case passportIso2 = "passport_iso2"
    }
}

/// Best short-stay status for one requested passport.
struct VisitorStatus: Codable, Sendable, Hashable {
    var passportIso2: String
    var status: VisaStatus
    var daysAllowed: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case passportIso2 = "passport_iso2"
        case daysAllowed = "days_allowed"
    }
}

extension URL {
    /// An http(s) URL from catalog text, or nil (the web's `isApplyUrl`).
    static func webLink(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    /// "https://www.sef.pt/en/visas" → "sef.pt" (the web's `sourceHost`).
    var displayHost: String? {
        guard let host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

import Foundation

/// Baseline visa regime for a (passport → destination) pair, from the
/// `visa_requirements` matrix. Drives the passport-strength map shading.
enum VisaStatus: String, Codable, CaseIterable, Sendable {
    case visaFree = "visa_free"
    case visaOnArrival = "visa_on_arrival"
    case evisa
    case visaRequired = "visa_required"
    case noAdmission = "no_admission"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisaStatus(rawValue: raw) ?? .unknown
    }

    /// Human label used in chips and legends.
    var label: String {
        switch self {
        case .visaFree: return "Visa-free"
        case .visaOnArrival: return "Visa on arrival"
        case .evisa: return "eVisa"
        case .visaRequired: return "Visa required"
        case .noAdmission: return "No admission"
        case .unknown: return "No data"
        }
    }

    /// Map/legend hue — saturated color is reserved for exactly this.
    var hue: StatusHue {
        switch self {
        case .visaFree: return .green
        case .visaOnArrival: return .teal
        case .evisa: return .blue
        case .visaRequired: return .yellow
        case .noAdmission: return .red
        case .unknown: return .purple // placeholder; rendered as neutral in the map
        }
    }
}

/// Entry type of a specific visa product.
enum EntryType: String, Codable, Sendable {
    case visaFree = "visa_free"
    case visaOnArrival = "visa_on_arrival"
    case evisa
    case eta
    case consular
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EntryType(rawValue: raw) ?? .unknown
    }
}

/// How VisaPassage handles a product: full service, prepare-only, or guidance.
enum ApplicationMode: String, Codable, Sendable {
    case ours
    case assisted
    case external
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApplicationMode(rawValue: raw) ?? .unknown
    }
}

/// Eligibility verdict for a passport against a product. Copy never promises
/// approval — only indicative eligibility.
enum VisaEligibility: String, Codable, Sendable {
    case eligible
    case conditional
    case notEligible = "not_eligible"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisaEligibility(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .eligible: return "Eligible"
        case .conditional: return "May be eligible"
        case .notEligible: return "Not eligible"
        case .unknown: return "Requires review"
        }
    }
}

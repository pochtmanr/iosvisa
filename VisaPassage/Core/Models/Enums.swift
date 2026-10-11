import SwiftUI

/// Baseline visa regime for a (passport → destination) pair, from the
/// `visa_requirements` matrix. Drives the passport-strength map shading.
enum VisaStatus: String, Codable, CaseIterable, Sendable {
    case visaFree = "visa_free"
    case visaOnArrival = "visa_on_arrival"
    case evisa
    /// Electronic travel authorisation (UK ETA, US ESTA, Canada eTA, …).
    case eta
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
        case .visaFree: return String(localized: "Visa-free")
        case .visaOnArrival: return String(localized: "Visa on arrival")
        case .evisa: return String(localized: "eVisa")
        case .eta: return String(localized: "eTA required")
        case .visaRequired: return String(localized: "Visa required")
        case .noAdmission: return String(localized: "No admission")
        case .unknown: return String(localized: "No data")
        }
    }

    /// Map/legend hue — saturated color is reserved for exactly this.
    var hue: StatusHue {
        switch self {
        case .visaFree: return .green
        case .visaOnArrival: return .teal
        case .evisa, .eta: return .blue
        case .visaRequired: return .yellow
        case .noAdmission: return .red
        case .unknown: return .purple // placeholder; rendered as neutral in the map
        }
    }

    /// Fill on the world map and its legend: the web hero map's own blue/yellow
    /// ramp (`--map-*` in `web/src/app/globals.css`), not the chip hues.
    var mapFill: Color {
        switch self {
        case .visaFree: return MapPalette.free
        case .visaOnArrival: return MapPalette.arrival
        case .evisa, .eta: return MapPalette.evisa
        case .visaRequired: return MapPalette.required
        case .noAdmission: return MapPalette.banned
        case .unknown: return MapPalette.unknown
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
        case .eligible: return String(localized: "Eligible")
        case .conditional: return String(localized: "May be eligible")
        case .notEligible: return String(localized: "Not eligible")
        case .unknown: return String(localized: "Requires review")
        }
    }
}

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

/// Canonical application status machine (mirrors the web `ApplicationStatus`).
/// Legacy values map onto the canonical set on decode.
enum ApplicationStatus: String, Codable, Sendable {
    case draft, ready, paid, offered, claimed
    case inProgress = "in_progress"
    case docsRequested = "docs_requested"
    case submittedToAuthority = "submitted_to_authority"
    case decisionPending = "decision_pending"
    case approved, refused, completed, cancelled, refunded
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "lead": self = .draft
        case "submitted": self = .submittedToAuthority
        case "in_review": self = .decisionPending
        case "rejected": self = .refused
        default: self = ApplicationStatus(rawValue: raw) ?? .unknown
        }
    }

    /// Coarse bucket used to group the applications list.
    enum Bucket { case needsAction, inProgress, complete }

    var bucket: Bucket {
        switch self {
        case .draft, .ready, .docsRequested: return .needsAction
        case .paid, .offered, .claimed, .inProgress, .submittedToAuthority, .decisionPending: return .inProgress
        case .approved, .refused, .completed, .cancelled, .refunded, .unknown: return .complete
        }
    }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .ready: return "Ready to pay"
        case .paid: return "Paid"
        case .offered: return "Finding an agent"
        case .claimed: return "Agent assigned"
        case .inProgress: return "In progress"
        case .docsRequested: return "Documents requested"
        case .submittedToAuthority: return "Submitted"
        case .decisionPending: return "Decision pending"
        case .approved: return "Approved"
        case .refused: return "Refused"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .refunded: return "Refunded"
        case .unknown: return "—"
        }
    }

    var hue: StatusHue {
        switch self {
        case .draft, .ready: return .yellow
        case .paid, .offered, .claimed, .inProgress, .docsRequested, .submittedToAuthority, .decisionPending: return .orange
        case .approved, .completed: return .green
        case .refused, .cancelled: return .red
        case .refunded, .unknown: return .purple
        }
    }
}

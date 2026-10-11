import Foundation

/// A row in `public.visa_applications` — the user's case for one visa product.
/// RLS scopes every read/write to the signed-in user. `applicant_details` is a
/// free-form `jsonb` blob (flat string keys filled from the vault, plus a few
/// structured flags like `details_confirmed`); we round-trip it faithfully as a
/// `[String: JSONValue]` so server-written keys (`history`, `consent_preview`)
/// are preserved through our patches. Mirrors the web `VisaApplication` type.
struct VisaApplication: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var userID: UUID
    var productID: UUID
    var passportIso2: String
    var destinationIso2: String
    var status: ApplicationStatus
    var applicantDetails: [String: JSONValue]
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case passportIso2 = "passport_iso2"
        case destinationIso2 = "destination_iso2"
        case status
        case applicantDetails = "applicant_details"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userID = try c.decode(UUID.self, forKey: .userID)
        productID = try c.decode(UUID.self, forKey: .productID)
        passportIso2 = (try c.decode(String.self, forKey: .passportIso2)).uppercased()
        destinationIso2 = (try c.decode(String.self, forKey: .destinationIso2)).uppercased()
        status = try c.decode(ApplicationStatus.self, forKey: .status)
        applicantDetails = (try c.decodeIfPresent([String: JSONValue].self, forKey: .applicantDetails)) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Typed view over `applicant_details` for the details form, prefill, and
    /// readiness — keeps all the jsonb key access in one place.
    var details: ApplicantDetails {
        get { ApplicantDetails(applicantDetails) }
        set { applicantDetails = newValue.values }
    }
}

/// A row in `public.application_status_events` — the audit/timeline trail.
/// Owners can read their own rows under RLS; the app never writes these (status
/// events are produced server-side by cron/webhooks), it only observes them.
struct ApplicationStatusEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var applicationID: UUID
    var fromStatus: ApplicationStatus?
    var toStatus: ApplicationStatus
    var actorRole: String?
    var note: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case applicationID = "application_id"
        case fromStatus = "from_status"
        case toStatus = "to_status"
        case actorRole = "actor_role"
        case note
        case createdAt = "created_at"
    }
}

/// A typed, mutating wrapper over the `applicant_details` `jsonb` dictionary.
/// String setters trim and drop empty values (so we never persist blank keys);
/// unknown keys already in `values` are preserved untouched on write-back.
struct ApplicantDetails: Sendable, Equatable {
    var values: [String: JSONValue]

    init(_ values: [String: JSONValue] = [:]) { self.values = values }

    /// Known flat keys shared with the web `applicant_details` shape.
    enum Key: String, CaseIterable {
        case legalFirstName = "legal_first_name"
        case legalMiddleName = "legal_middle_name"
        case legalLastName = "legal_last_name"
        case dateOfBirth = "date_of_birth"
        case placeOfBirth = "place_of_birth"
        case genderOnPassport = "gender_on_passport"
        case maritalStatus = "marital_status"
        case passportNumber = "passport_number"
        case passportExpiry = "passport_expiry"
        case phone
        case plannedEntryDate = "planned_entry_date"
        case plannedDurationDays = "planned_duration_days"
        case priorVisits = "prior_visits"
        case priorVisitsNote = "prior_visits_note"
    }

    enum Flag: String {
        case detailsConfirmed = "details_confirmed"
        case documentsAcknowledged = "documents_acknowledged"
    }

    // MARK: String access

    func string(_ key: Key) -> String { values[key.rawValue]?.stringValue ?? "" }

    mutating func set(_ key: Key, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { values[key.rawValue] = nil }
        else { values[key.rawValue] = .string(trimmed) }
    }

    // MARK: Flag access

    func flag(_ flag: Flag) -> Bool { values[flag.rawValue]?.boolValue ?? false }

    mutating func setFlag(_ flag: Flag, _ on: Bool) { values[flag.rawValue] = .bool(on) }

    /// True once the user has confirmed the prefilled applicant details.
    var detailsConfirmed: Bool { flag(.detailsConfirmed) }
    /// True once the user has acknowledged they hold the required documents.
    /// (Real attachment lands in M4; this is the M3 documents gate, mirroring
    /// the web pre-flight `documents_acknowledged` flag.)
    var documentsAcknowledged: Bool { flag(.documentsAcknowledged) }
}

import Foundation

/// A row in `public.profiles` (1:1 with `auth.users`). All vault fields are
/// optional and filled progressively through onboarding. Mirrors the web
/// `Profile` type plus the migration-0010 vault columns.
///
/// Postgres `date` columns are modelled as ISO `"yyyy-MM-dd"` strings (see
/// `DateOnly`) so JSON encode/decode is unambiguous and matches the web client.
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var fullName: String?
    var accountType: String?

    // Vault — legal identity
    var legalFirstName: String?
    var legalMiddleName: String?
    var legalLastName: String?
    var previousNames: [PreviousName]?
    var dateOfBirth: String?            // "yyyy-MM-dd"
    var placeOfBirth: String?
    var genderOnPassport: String?
    var maritalStatus: String?
    var nationalIDs: [String: String]?  // { iso2: id_number }

    // Vault — contact
    var phone: String?
    var residentialAddress: PostalAddress?
    var mailingAddress: PostalAddress?
    var emergencyContact: EmergencyContact?

    var avatarPath: String?

    // Onboarding
    var goal: [String]?
    var onboardingCompletedAt: Date?

    // Notifications
    var notifyEmail: Bool?
    var notifyMessages: Bool?
    var notifyProduct: Bool?

    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case accountType = "account_type"
        case legalFirstName = "legal_first_name"
        case legalMiddleName = "legal_middle_name"
        case legalLastName = "legal_last_name"
        case previousNames = "previous_names"
        case dateOfBirth = "date_of_birth"
        case placeOfBirth = "place_of_birth"
        case genderOnPassport = "gender_on_passport"
        case maritalStatus = "marital_status"
        case nationalIDs = "national_ids"
        case phone
        case residentialAddress = "residential_address"
        case mailingAddress = "mailing_address"
        case emergencyContact = "emergency_contact"
        case avatarPath = "avatar_path"
        case goal
        case onboardingCompletedAt = "onboarding_completed_at"
        case notifyEmail = "notify_email"
        case notifyMessages = "notify_messages"
        case notifyProduct = "notify_product"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Coarse "wizard not yet finished" flag. The full gate (web parity) also
    /// considers whether the user already holds a passport — see
    /// `AuthStore.loadProfile`.
    var needsOnboarding: Bool { onboardingCompletedAt == nil }

    /// Best display name for greetings.
    var displayName: String? {
        if let f = legalFirstName, !f.isEmpty { return f }
        if let n = fullName, !n.isEmpty { return n }
        return nil
    }
}

/// A `profiles.previous_names` jsonb element.
struct PreviousName: Codable, Hashable, Sendable {
    var first: String?
    var middle: String?
    var last: String?
}

/// A structured postal address stored as jsonb (`residential_address` /
/// `mailing_address`). Mirrors the web `PostalAddress` shape.
struct PostalAddress: Codable, Hashable, Sendable {
    var line1: String?
    var line2: String?
    var city: String?
    var region: String?
    var postalCode: String?
    var countryISO2: String?

    enum CodingKeys: String, CodingKey {
        case line1, line2, city, region
        case postalCode = "postal_code"
        case countryISO2 = "country_iso2"
    }

    /// True when every field is empty/absent — used to send `null` instead of
    /// an all-blank object.
    var isEmpty: Bool {
        [line1, line2, city, region, postalCode, countryISO2]
            .allSatisfy { ($0 ?? "").isEmpty }
    }

    /// One-line summary for list rows.
    var summary: String {
        [line1, line2, city, region, postalCode, countryISO2]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// `profiles.emergency_contact` jsonb shape.
struct EmergencyContact: Codable, Hashable, Sendable {
    var fullName: String?
    var relationship: String?
    var phone: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case relationship, phone, email
    }

    var isEmpty: Bool {
        [fullName, relationship, phone, email].allSatisfy { ($0 ?? "").isEmpty }
    }
}

/// A row in `public.passports` — the multi-passport vault.
struct Passport: Codable, Identifiable, Sendable {
    let id: UUID
    var citizenshipISO2: String?
    var passportNumber: String?
    var issueDate: String?              // "yyyy-MM-dd"
    var expiryDate: String?            // "yyyy-MM-dd"
    var issuingAuthority: String?
    var placeOfIssue: String?
    var isPrimary: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case citizenshipISO2 = "citizenship_iso2"
        case passportNumber = "passport_number"
        case issueDate = "issue_date"
        case expiryDate = "expiry_date"
        case issuingAuthority = "issuing_authority"
        case placeOfIssue = "place_of_issue"
        case isPrimary = "is_primary"
    }
}

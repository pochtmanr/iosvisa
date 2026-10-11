import Foundation

/// The five repeating vault tables, mirroring the migration-0010 schema. Each
/// is `user_id`-scoped under RLS; `*_iso2` columns are two-letter country codes;
/// `date` columns are ISO `"yyyy-MM-dd"` strings (see `DateOnly`).

/// A row in `public.residencies` — residence permits the user holds.
struct Residency: Codable, Identifiable, Sendable {
    let id: UUID
    var countryISO2: String?
    var permitType: String?
    var permitNumber: String?
    var issueDate: String?
    var expiryDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case countryISO2 = "country_iso2"
        case permitType = "permit_type"
        case permitNumber = "permit_number"
        case issueDate = "issue_date"
        case expiryDate = "expiry_date"
    }
}

/// `public.family_members.relationship` enum.
enum FamilyRelationship: String, Codable, CaseIterable, Sendable, Identifiable {
    case spouse, child, parent, dependent
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A row in `public.family_members`.
struct FamilyMember: Codable, Identifiable, Sendable {
    let id: UUID
    var relationship: FamilyRelationship
    var fullName: String?
    var dateOfBirth: String?
    var citizenshipISO2: String?

    enum CodingKeys: String, CodingKey {
        case id, relationship
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case citizenshipISO2 = "citizenship_iso2"
    }
}

/// A row in `public.employment_entries`.
struct EmploymentEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var status: String?
    var employer: String?
    var jobTitle: String?
    var employerAddress: String?
    var startDate: String?
    var incomeRange: String?
    var selfEmployed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, status, employer
        case jobTitle = "job_title"
        case employerAddress = "employer_address"
        case startDate = "start_date"
        case incomeRange = "income_range"
        case selfEmployed = "self_employed"
    }
}

/// A row in `public.education_entries`.
struct EducationEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var level: String?
    var institution: String?
    var fieldOfStudy: String?
    var startDate: String?
    var endDate: String?

    enum CodingKeys: String, CodingKey {
        case id, level, institution
        case fieldOfStudy = "field_of_study"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// A row in `public.travel_entries`.
struct TravelEntry: Codable, Identifiable, Sendable {
    let id: UUID
    var countryISO2: String?
    var enteredOn: String?
    var exitedOn: String?
    var purpose: String?
    var hadVisa: Bool?
    var wasRefused: Bool?
    var overstayed: Bool?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case countryISO2 = "country_iso2"
        case enteredOn = "entered_on"
        case exitedOn = "exited_on"
        case purpose
        case hadVisa = "had_visa"
        case wasRefused = "was_refused"
        case overstayed
        case notes
    }
}

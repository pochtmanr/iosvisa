import Foundation

/// Partial `profiles` update payloads. Only the columns present here are written
/// (a section form owns its whole section, so sending `null` to clear a field is
/// intentional). Snake-case property names map straight to the columns.

struct PersonalPatch: Encodable, Sendable {
    let legal_first_name: String?
    let legal_middle_name: String?
    let legal_last_name: String?
    let date_of_birth: String?
    let place_of_birth: String?
    let gender_on_passport: String?
    let marital_status: String?
}

struct ContactPatch: Encodable, Sendable {
    let phone: String?
    let residential_address: PostalAddress?
    let mailing_address: PostalAddress?
    let emergency_contact: EmergencyContact?
}

/// Onboarding "finish" — identity + goal + completion stamp in one update.
struct OnboardingFinishPatch: Encodable, Sendable {
    let goal: [String]?
    let legal_first_name: String?
    let legal_middle_name: String?
    let legal_last_name: String?
    let date_of_birth: String?
    let place_of_birth: String?
    let gender_on_passport: String?
    let marital_status: String?
    let onboarding_completed_at: String
}

/// Onboarding "skip" — just stamp completion so the user reaches the app.
struct OnboardingSkipPatch: Encodable, Sendable {
    let onboarding_completed_at: String
}

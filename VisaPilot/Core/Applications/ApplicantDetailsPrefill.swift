import Foundation

/// Builds the initial `applicant_details` for a new application by seeding from
/// the profile vault + the chosen passport — the iOS port of the web
/// `startApplication` server action's prefill cascade.
///
/// Identity fields come from `profiles`; passport number/expiry from the chosen
/// `passports` row. Empty/nil values are omitted (the `ApplicantDetails` setters
/// drop blanks) so we never persist empty keys. Pure → unit-tested.
enum ApplicantDetailsPrefill {
    static func make(from profile: Profile?, passport: Passport?) -> ApplicantDetails {
        var details = ApplicantDetails()
        if let profile {
            details.set(.legalFirstName, profile.legalFirstName ?? "")
            details.set(.legalMiddleName, profile.legalMiddleName ?? "")
            details.set(.legalLastName, profile.legalLastName ?? "")
            details.set(.dateOfBirth, profile.dateOfBirth ?? "")
            details.set(.placeOfBirth, profile.placeOfBirth ?? "")
            details.set(.genderOnPassport, profile.genderOnPassport ?? "")
            details.set(.maritalStatus, profile.maritalStatus ?? "")
            details.set(.phone, profile.phone ?? "")
        }
        if let passport {
            details.set(.passportNumber, passport.passportNumber ?? "")
            details.set(.passportExpiry, passport.expiryDate ?? "")
        }
        return details
    }
}

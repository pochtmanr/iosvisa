import Foundation

/// A row in `public.profiles` (1:1 with `auth.users`). Only the columns the
/// app reads are modelled; the marketplace-era vault columns still exist in the
/// table but are ignored here.
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var fullName: String?
    var avatarPath: String?
    /// Onboarding goals (`profiles.goal`, migration 0036): marks the matching
    /// purpose card "Your goal".
    var goal: [String]?

    // Notifications
    var notifyEmail: Bool?
    var notifyMessages: Bool?
    var notifyProduct: Bool?

    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarPath = "avatar_path"
        case goal
        case notifyEmail = "notify_email"
        case notifyMessages = "notify_messages"
        case notifyProduct = "notify_product"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Best display name for greetings.
    var displayName: String? {
        if let n = fullName, !n.isEmpty { return n }
        return nil
    }
}

/// A row in `public.passports`. Only the citizenship is read, to seed the
/// visa-checker selection for a signed-in user.
struct Passport: Codable, Identifiable, Sendable {
    let id: UUID
    var citizenshipISO2: String?
    var isPrimary: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case citizenshipISO2 = "citizenship_iso2"
        case isPrimary = "is_primary"
    }
}

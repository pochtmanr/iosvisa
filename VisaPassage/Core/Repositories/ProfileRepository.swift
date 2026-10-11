import Foundation
import Supabase

/// Reads and writes the signed-in user's `profiles` row (and passports) via
/// PostgREST. RLS guarantees the user only ever sees their own data.
struct ProfileRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// Fetch the current user's profile, or nil if the row doesn't exist yet.
    func currentProfile() async throws -> Profile? {
        let userID = try await client.auth.session.user.id
        let rows: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Insert a bare profile row for a brand-new user (id = auth uid).
    @discardableResult
    func ensureProfile() async throws -> Profile {
        if let existing = try await currentProfile() { return existing }
        let userID = try await client.auth.session.user.id
        struct NewProfile: Encodable { let id: UUID }
        let created: Profile = try await client
            .from("profiles")
            .insert(NewProfile(id: userID), returning: .representation)
            .single()
            .execute()
            .value
        return created
    }

    /// List the user's passports (drives the visa-checker default selection),
    /// primary first then newest.
    func passports() async throws -> [Passport] {
        try await client
            .from("passports")
            .select("id,citizenship_iso2,is_primary")
            .order("is_primary", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}

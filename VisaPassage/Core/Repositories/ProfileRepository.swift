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
            .select()
            .order("is_primary", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// How many passports the user holds — part of the onboarding gate (web
    /// treats "has ≥1 passport" as already onboarded).
    func passportCount() async throws -> Int {
        struct IDRow: Decodable { let id: UUID }
        let rows: [IDRow] = try await client
            .from("passports")
            .select("id")
            .execute()
            .value
        return rows.count
    }

    /// Patch the current user's `profiles` row with the given encodable payload
    /// (only the columns present in `patch` are written) and return the row.
    @discardableResult
    func updateProfile<Body: Encodable & Sendable>(_ patch: Body) async throws -> Profile {
        let userID = try await client.auth.session.user.id
        return try await client
            .from("profiles")
            .update(patch, returning: .representation)
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    /// The current user's id (equals `profiles.id` / `auth.uid()`), used to
    /// stamp `user_id` on vault inserts.
    func currentUserID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    /// Row counts for each repeating vault section (RLS-scoped). Drives the
    /// dashboard completeness ring and the workspace readiness gate.
    func vaultSectionCounts() async throws -> VaultSectionCounts {
        async let residencies = count("residencies")
        async let education = count("education_entries")
        async let employment = count("employment_entries")
        async let family = count("family_members")
        async let travel = count("travel_entries")
        async let background = count("background_declarations")
        return try await VaultSectionCounts(
            residencies: residencies,
            education: education,
            employment: employment,
            family: family,
            travel: travel,
            background: background
        )
    }

    /// How many documents the user has stored in their vault (`user_documents`).
    func documentsCount() async throws -> Int { try await count("user_documents") }

    /// Count rows the user owns in a table (a thin `select id` — RLS scopes it).
    private func count(_ table: String) async throws -> Int {
        struct IDRow: Decodable { let id: UUID }
        let rows: [IDRow] = try await client
            .from(table)
            .select("id")
            .execute()
            .value
        return rows.count
    }
}

/// Per-section row counts for the repeating vault tables.
struct VaultSectionCounts: Sendable, Equatable {
    var residencies: Int = 0
    var education: Int = 0
    var employment: Int = 0
    var family: Int = 0
    var travel: Int = 0
    var background: Int = 0
}

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

    // MARK: Edits (RLS: profiles_update_own)

    func update(fullName: String?) async throws {
        struct Patch: Encodable { let full_name: String? }
        try await patch(Patch(full_name: fullName))
    }

    func update(avatarPath: String?) async throws {
        struct Patch: Encodable { let avatar_path: String? }
        try await patch(Patch(avatar_path: avatarPath))
    }

    private func patch(_ value: some Encodable & Sendable) async throws {
        let userID = try await client.auth.session.user.id
        try await client.from("profiles").update(value).eq("id", value: userID).execute()
    }

    // MARK: Avatar (public `branding` bucket, as the web's settings actions)

    /// Upload a JPEG under `avatars/{uid}/` (the only folder the
    /// `branding_avatar_write_own` policy allows) and return its path.
    func uploadAvatar(jpeg: Data) async throws -> String {
        let userID = try await client.auth.session.user.id
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        let path = "avatars/\(userID.uuidString.lowercased())/\(millis).jpg"
        try await client.storage.from("branding")
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    /// Best effort: a leftover object is harmless.
    func removeAvatar(_ path: String) async {
        _ = try? await client.storage.from("branding").remove(paths: [path])
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

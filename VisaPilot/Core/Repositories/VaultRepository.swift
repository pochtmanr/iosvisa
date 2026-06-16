import Foundation
import Supabase

/// Generic CRUD over the user's `user_id`-scoped vault tables. RLS guarantees
/// every read/write only ever touches the signed-in user's rows; callers pass
/// the table name and Codable payloads (insert payloads include `user_id`,
/// which equals `profiles.id` / `auth.uid()`).
struct VaultRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// Table names, kept in one place to avoid typos across the vault UI.
    enum Table: String {
        case passports
        case residencies
        case familyMembers = "family_members"
        case employmentEntries = "employment_entries"
        case educationEntries = "education_entries"
        case travelEntries = "travel_entries"
    }

    /// List all rows for the current user, newest first.
    func list<T: Decodable & Sendable>(_ table: Table, as type: T.Type = T.self) async throws -> [T] {
        try await client
            .from(table.rawValue)
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Insert a row and return the stored representation.
    @discardableResult
    func insert<Row: Decodable & Sendable, Body: Encodable & Sendable>(
        _ table: Table, _ body: Body, as type: Row.Type = Row.self
    ) async throws -> Row {
        try await client
            .from(table.rawValue)
            .insert(body, returning: .representation)
            .single()
            .execute()
            .value
    }

    /// Update a row by id and return the stored representation.
    @discardableResult
    func update<Row: Decodable & Sendable, Body: Encodable & Sendable>(
        _ table: Table, id: UUID, _ body: Body, as type: Row.Type = Row.self
    ) async throws -> Row {
        try await client
            .from(table.rawValue)
            .update(body, returning: .representation)
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    /// Delete a row by id.
    func delete(_ table: Table, id: UUID) async throws {
        _ = try await client
            .from(table.rawValue)
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: Passports — single-primary enforcement (mirrors web actions)

    /// Demote every other passport for this user before promoting one. Pass the
    /// row being edited as `except` so it isn't demoted by its own save.
    func demoteOtherPrimaryPassports(userID: UUID, except id: UUID? = nil) async throws {
        struct PrimaryPatch: Encodable, Sendable { let is_primary: Bool }
        var query = try client
            .from(Table.passports.rawValue)
            .update(PrimaryPatch(is_primary: false))
            .eq("user_id", value: userID)
        if let id {
            query = query.neq("id", value: id)
        }
        _ = try await query.execute()
    }
}

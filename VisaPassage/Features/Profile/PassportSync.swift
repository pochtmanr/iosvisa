import Foundation
import Supabase

/// Keeps the on-device passport selection (`PassportPreference`) and the
/// signed-in user's `passports` rows in step. RLS scopes every query to the
/// user, so no user id is passed.
///
/// - On sign-in the account wins: a non-empty server list replaces the local one.
/// - After that, local edits are pushed: missing countries are inserted,
///   `is_primary` follows the local order, and a removed country's row is
///   deleted only when it holds no document details (number, expiry) entered on
///   the web, so the app never destroys vault data.
@MainActor
struct PassportSync {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// The columns the sync reads.
    struct Row: Codable, Equatable, Sendable {
        let id: UUID
        var citizenshipISO2: String?
        var isPrimary: Bool?
        var passportNumber: String?
        var expiryDate: String?

        enum CodingKeys: String, CodingKey {
            case id
            case citizenshipISO2 = "citizenship_iso2"
            case isPrimary = "is_primary"
            case passportNumber = "passport_number"
            case expiryDate = "expiry_date"
        }

        /// Holds details the user typed on the web, so it must not be deleted.
        var hasDocumentDetails: Bool {
            !(passportNumber ?? "").isEmpty || !(expiryDate ?? "").isEmpty
        }
    }

    /// What a push changes. Pure, so it is unit-tested.
    struct Plan: Equatable {
        var insert: [(iso2: String, primary: Bool)]
        var setPrimary: [(id: UUID, primary: Bool)]
        var delete: [UUID]

        static func == (a: Plan, b: Plan) -> Bool {
            a.insert.map { "\($0.iso2)\($0.primary)" } == b.insert.map { "\($0.iso2)\($0.primary)" }
                && a.setPrimary.map { "\($0.id)\($0.primary)" } == b.setPrimary.map { "\($0.id)\($0.primary)" }
                && a.delete == b.delete
        }

        var isEmpty: Bool { insert.isEmpty && setPrimary.isEmpty && delete.isEmpty }
    }

    /// The server list as the app's selection: primary first, then newest.
    static func selection(from rows: [Row]) -> [String] {
        let primaryFirst = rows.filter { $0.isPrimary == true } + rows.filter { $0.isPrimary != true }
        return PassportPreference.clean(primaryFirst.compactMap { $0.citizenshipISO2 })
    }

    /// Diff the local selection (primary first) against the server rows.
    nonisolated static func plan(local: [String], remote: [Row]) -> Plan {
        let local = local.map { $0.uppercased() }
        var insert: [(String, Bool)] = []
        var setPrimary: [(UUID, Bool)] = []
        var delete: [UUID] = []
        var matched = Set<UUID>()

        for (index, iso) in local.enumerated() {
            let wantPrimary = index == 0
            if let row = remote.first(where: { $0.citizenshipISO2?.uppercased() == iso && !matched.contains($0.id) }) {
                matched.insert(row.id)
                if (row.isPrimary ?? false) != wantPrimary { setPrimary.append((row.id, wantPrimary)) }
            } else {
                insert.append((iso, wantPrimary))
            }
        }
        for row in remote where !matched.contains(row.id) {
            if row.hasDocumentDetails {
                // Kept, but it can no longer be the primary one.
                if row.isPrimary == true { setPrimary.append((row.id, false)) }
            } else {
                delete.append(row.id)
            }
        }
        return Plan(insert: insert.map { (iso2: $0.0, primary: $0.1) },
                    setPrimary: setPrimary.map { (id: $0.0, primary: $0.1) },
                    delete: delete)
    }

    func fetch() async throws -> [Row] {
        try await client
            .from("passports")
            .select("id,citizenship_iso2,is_primary,passport_number,expiry_date")
            .order("is_primary", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Sign-in: adopt the account's passports when it has any, otherwise push
    /// the device's selection up.
    func pull(into preference: PassportPreference) async {
        guard let rows = try? await fetch() else { return }
        let remote = Self.selection(from: rows)
        if remote.isEmpty {
            await push(preference.passports, remote: rows)
        } else if remote != preference.passports {
            preference.set(remote)
        }
    }

    /// Push the local selection. Errors are swallowed: the device copy stays
    /// the source of truth and the next change retries.
    func push(_ local: [String], remote: [Row]? = nil) async {
        var rows = remote
        if rows == nil { rows = try? await fetch() }
        guard let rows else { return }
        let plan = Self.plan(local: local, remote: rows)
        guard !plan.isEmpty else { return }
        do {
            let userID = try await client.auth.session.user.id
            // Clear primaries first: at most one row should be primary.
            for change in plan.setPrimary where !change.primary {
                try await client.from("passports").update(["is_primary": false]).eq("id", value: change.id).execute()
            }
            for change in plan.setPrimary where change.primary {
                try await client.from("passports").update(["is_primary": true]).eq("id", value: change.id).execute()
            }
            if !plan.insert.isEmpty {
                struct NewRow: Encodable {
                    let user_id: UUID
                    let citizenship_iso2: String
                    let is_primary: Bool
                }
                try await client.from("passports")
                    .insert(plan.insert.map { NewRow(user_id: userID, citizenship_iso2: $0.iso2, is_primary: $0.primary) })
                    .execute()
            }
            if !plan.delete.isEmpty {
                try await client.from("passports").delete().in("id", values: plan.delete).execute()
            }
        } catch {
            // Best effort; see above.
        }
    }
}

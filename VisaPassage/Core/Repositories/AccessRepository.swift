import Foundation
import Supabase

/// Decides which portal the signed-in account belongs to, mirroring the web
/// `getPortalAccess()` / `resolvePortalDestination()` in
/// `web/src/lib/auth/portals.ts`: admins run the platform, agency members work
/// cases, everyone else is a traveler. In v1 iOS **everyone uses the end-user
/// app** — this only drives a "manage your portal on the web" notice.
struct AccessRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    enum Portal: Equatable, Sendable {
        case endUser
        case agency(status: String)
        case admin
    }

    func currentPortal() async throws -> Portal {
        let userID = try await client.auth.session.user.id

        struct AdminRow: Decodable { let user_id: UUID }
        let admins: [AdminRow] = try await client
            .from("admin_users")
            .select("user_id")
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        if !admins.isEmpty { return .admin }

        struct MemberRow: Decodable { let status: String }
        let members: [MemberRow] = try await client
            .from("agency_members")
            .select("status")
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        if let member = members.first { return .agency(status: member.status) }

        return .endUser
    }
}

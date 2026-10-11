import Foundation
import Supabase

/// Reads the public `countries` catalog (no auth required). Used by the country
/// pickers across the vault and onboarding.
struct CountryRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// All countries, alphabetical by name.
    func all() async throws -> [Country] {
        try await client
            .from("countries")
            .select("iso2,name,region,flag_emoji,is_passport,iso_numeric,slug,coverage_tier")
            .order("name", ascending: true)
            .execute()
            .value
    }
}

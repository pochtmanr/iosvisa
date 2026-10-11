import Foundation
import Supabase

/// Reads the public visa-intelligence catalog (no auth required): the bilateral
/// `visa_requirements` matrix that shades the map, and the resolved
/// `visa_products` for a destination. Mirrors the web `loadDestinationVisaOptions`
/// in `web/src/lib/visa-products.ts`.
struct VisaRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// PostgREST returns at most 1000 rows per request. A single passport has
    /// ~250 destination rows today, but we page to stay correct as data grows.
    private static let pageSize = 1000

    // MARK: Map shading

    /// Every `visa_requirements` row for one passport, across all destinations.
    func requirements(passport: String) async throws -> [VisaRequirement] {
        let iso = passport.uppercased()
        var all: [VisaRequirement] = []
        var offset = 0
        while true {
            let page: [VisaRequirement] = try await client
                .from("visa_requirements")
                .select("passport_iso2,destination_iso2,status,days_allowed,notes")
                .eq("passport_iso2", value: iso)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        return all
    }

    /// Best status per destination across several passports (map / grid shading).
    func bestStatuses(passports: [String]) async throws -> [String: VisaStatus] {
        guard !passports.isEmpty else { return [:] }
        var rows: [VisaRequirement] = []
        for passport in passports {
            rows.append(contentsOf: try await requirements(passport: passport))
        }
        return VisaStatus.bestByDestination(rows)
    }

    // MARK: Destination routes

    /// Resolved visa products for a (passport → destination) pair. Port of the
    /// web `loadDestinationVisaOptions`: expand zones, select active products for
    /// the destination or any of its zones, fold sparse eligibility overrides.
    func destinationOptions(passport: String, destination: String) async throws -> DestinationVisaOptions {
        let passportISO = passport.uppercased()
        let destISO = destination.uppercased()

        // 1. Expand the destination to any zones it belongs to (e.g. Schengen).
        struct ZoneRow: Decodable { let zone_code: String }
        let zoneRows: [ZoneRow] = try await client
            .from("visa_zone_members")
            .select("zone_code")
            .eq("member_iso2", value: destISO)
            .execute()
            .value
        let zoneCodes = Array(Set(zoneRows.map(\.zone_code)))

        // 2. Active products for this destination OR any of its zones.
        var orFilter = "destination_iso2.eq.\(destISO)"
        if !zoneCodes.isEmpty {
            orFilter += ",zone_code.in.(\(zoneCodes.joined(separator: ",")))"
        }
        let products: [VisaProduct] = try await client
            .from("visa_products")
            .select()
            .eq("is_active", value: true)
            .or(orFilter)
            .order("sort_order", ascending: true)
            .execute()
            .value

        // 3. Sparse per-nationality overrides for those products.
        var overridesByProduct: [UUID: VisaProductEligibility] = [:]
        if !products.isEmpty {
            let ids = products.map { $0.id.uuidString }
            let overrides: [VisaProductEligibility] = try await client
                .from("visa_product_eligibility")
                .select()
                .in("product_id", values: ids)
                .eq("passport_iso2", value: passportISO)
                .execute()
                .value
            for o in overrides { overridesByProduct[o.productID] = o }
        }

        // 4. Fold overrides into effective values.
        let resolved = products.map { product in
            ResolvedVisaProduct.resolve(product, override: overridesByProduct[product.id])
        }

        return DestinationVisaOptions(
            passportIso2: passportISO,
            destinationIso2: destISO,
            products: resolved
        )
    }

    /// Baseline regime for the chip at the top of the destination detail.
    func baselineStatus(passport: String, destination: String) async throws -> VisaRequirement? {
        let rows: [VisaRequirement] = try await client
            .from("visa_requirements")
            .select("passport_iso2,destination_iso2,status,days_allowed,notes")
            .eq("passport_iso2", value: passport.uppercased())
            .eq("destination_iso2", value: destination.uppercased())
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}

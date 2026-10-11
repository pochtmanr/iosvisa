import Foundation
import Observation
import Supabase

/// Routes per destination for one non-travel purpose: a Swift port of the web
/// `GET /api/visa-checker/purposes` (`web/src/app/api/visa-checker/purposes/route.ts`),
/// read straight from the public catalog tables. The route itself sits behind
/// the checker's browser-only abuse guard (BotID), so a native client asks
/// PostgREST and folds the rows here, exactly as the route does.
///
/// Legacy catalog data → "Unverified" in the UI.
struct PurposeRoutesRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared

    /// Product ids per eligibility request.
    private static let idBatch = 150

    struct ProductRow: Decodable, Sendable {
        let id: UUID
        let code: String
        let name: String
        let visaTypeCode: String
        let destinationIso2: String?
        let zoneCode: String?
        let maxStayDays: Int?
        let processingTimeDays: Int?
        let defaultEligibility: VisaEligibility
        let sortOrder: Int?
        let translations: Translations?
        let attributes: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case id, code, name, translations, attributes
            case visaTypeCode = "visa_type_code"
            case destinationIso2 = "destination_iso2"
            case zoneCode = "zone_code"
            case maxStayDays = "max_stay_days"
            case processingTimeDays = "processing_time_days"
            case defaultEligibility = "default_eligibility"
            case sortOrder = "sort_order"
        }
    }

    struct TypeRow: Decodable, Sendable {
        let code: String
        let name: String
        let translations: Translations?
    }

    struct ZoneMemberRow: Decodable, Sendable {
        let zoneCode: String
        let memberIso2: String
        enum CodingKeys: String, CodingKey {
            case zoneCode = "zone_code"
            case memberIso2 = "member_iso2"
        }
    }

    struct OverrideRow: Decodable, Sendable {
        let productId: UUID
        let eligibility: VisaEligibility
        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case eligibility
        }
    }

    /// Fetch and fold. `passports` is optional, as on the web: when given, the
    /// sparse `visa_product_eligibility` overrides apply (best across passports).
    func routes(purpose: Purpose, passports: [String], locale: AppLocale = .current) async throws -> CheckerRoutes {
        let typeCodes = purpose.typeCodes
        guard purpose.isRoute else { return CheckerRoutes(purpose: purpose, types: [], destinations: [:]) }

        async let productsTask: [ProductRow] = client
            .from("visa_products")
            .select("id,code,name,visa_type_code,destination_iso2,zone_code,max_stay_days,processing_time_days,default_eligibility,sort_order,translations,attributes")
            .eq("is_active", value: true)
            .in("visa_type_code", values: typeCodes)
            .execute()
            .value
        async let typesTask: [TypeRow] = client
            .from("visa_types")
            .select("code,name,translations")
            .in("code", values: typeCodes)
            .execute()
            .value
        let (products, types) = try await (productsTask, typesTask)

        let zoneCodes = Array(Set(products.compactMap(\.zoneCode)))
        var members: [ZoneMemberRow] = []
        if !zoneCodes.isEmpty {
            members = try await client
                .from("visa_zone_members")
                .select("zone_code,member_iso2")
                .in("zone_code", values: zoneCodes)
                .execute()
                .value
        }

        let wanted = Self.parsePassports(passports)
        var overrides: [OverrideRow] = []
        if !wanted.isEmpty, !products.isEmpty {
            // Work has 500+ products: batch the ids so the GET stays well under
            // URL length limits (same rows as the web's single query).
            let ids = products.map { $0.id.uuidString }
            for start in stride(from: 0, to: ids.count, by: Self.idBatch) {
                let batch = Array(ids[start..<min(start + Self.idBatch, ids.count)])
                let rows: [OverrideRow] = try await client
                    .from("visa_product_eligibility")
                    .select("product_id,eligibility")
                    .in("passport_iso2", values: wanted)
                    .in("product_id", values: batch)
                    .execute()
                    .value
                overrides += rows
            }
        }

        return Self.fold(purpose: purpose, products: products, types: types,
                         members: members, overrides: overrides, locale: locale)
    }

    /// Valid ISO2, deduped, the first five as sent, then sorted (`parsePassports`).
    static func parsePassports(_ passports: [String]) -> [String] {
        var seen: [String] = []
        for raw in passports {
            let iso = raw.uppercased()
            guard iso.count == 2, iso.allSatisfy({ $0.isASCII && $0.isLetter }), !seen.contains(iso) else { continue }
            seen.append(iso)
            if seen.count == 5 { break }
        }
        return seen.sorted()
    }

    private static func rank(_ e: VisaEligibility) -> Int {
        switch e {
        case .eligible: return 0
        case .conditional: return 1
        case .notEligible: return 2
        case .unknown: return 3
        }
    }

    /// The route's pure fold, kept separate for the tests: overrides (best
    /// wins), type order then `sort_order`, zone expansion, one route per code
    /// per destination, and only the types that have a route.
    static func fold(
        purpose: Purpose,
        products: [ProductRow],
        types: [TypeRow],
        members: [ZoneMemberRow],
        overrides: [OverrideRow],
        locale: AppLocale
    ) -> CheckerRoutes {
        var membersByZone: [String: [String]] = [:]
        for m in members {
            membersByZone[m.zoneCode, default: []].append(m.memberIso2.uppercased())
        }

        var overrideByProduct: [UUID: VisaEligibility] = [:]
        for o in overrides {
            if let cur = overrideByProduct[o.productId], rank(cur) <= rank(o.eligibility) { continue }
            overrideByProduct[o.productId] = o.eligibility
        }

        let typeOrder = Dictionary(uniqueKeysWithValues: purpose.typeCodes.enumerated().map { ($1, $0) })
        // Stable sort, like Array.prototype.sort.
        let sorted = products.enumerated().sorted { a, b in
            let ta = typeOrder[a.element.visaTypeCode] ?? 99
            let tb = typeOrder[b.element.visaTypeCode] ?? 99
            if ta != tb { return ta < tb }
            let sa = a.element.sortOrder ?? 0
            let sb = b.element.sortOrder ?? 0
            if sa != sb { return sa < sb }
            return a.offset < b.offset
        }.map(\.element)

        var destinations: [String: [CheckerRoute]] = [:]
        for p in sorted {
            let route = CheckerRoute(
                id: p.id,
                code: p.code,
                name: pickTranslation(p.translations, field: "name", english: p.name, locale: locale),
                visaTypeCode: p.visaTypeCode,
                maxStayDays: p.maxStayDays,
                processingTimeDays: p.processingTimeDays,
                eligibility: overrideByProduct[p.id] ?? p.defaultEligibility,
                rights: CheckerRouteRight.parse(p.attributes ?? [:])
            )
            let targets: [String]
            if let dest = p.destinationIso2 {
                targets = [dest.uppercased()]
            } else if let zone = p.zoneCode {
                targets = membersByZone[zone] ?? []
            } else {
                targets = []
            }
            for iso in targets {
                var list = destinations[iso] ?? []
                if !list.contains(where: { $0.code == route.code }) { list.append(route) }
                destinations[iso] = list
            }
        }

        let present = Set(products.map(\.visaTypeCode))
        let typeList = types
            .filter { present.contains($0.code) }
            .sorted { (typeOrder[$0.code] ?? 99) < (typeOrder[$1.code] ?? 99) }
            .map { CheckerRoutes.VisaType(code: $0.code,
                                          name: pickTranslation($0.translations, field: "name", english: $0.name, locale: locale)) }

        return CheckerRoutes(purpose: purpose, types: typeList, destinations: destinations)
    }
}

// MARK: - Store

/// App-wide purpose routes for Explore. Every response is kept by purpose and
/// passport set, as the web checker keeps its responses, so switching purposes
/// back and forth is instant.
@MainActor
@Observable
final class PurposeRoutesStore {
    private(set) var current: CheckerRoutes?
    private(set) var loading = false
    private(set) var failed = false

    private var cache: [String: CheckerRoutes] = [:]
    private var wantedKey: String?
    private let repo: PurposeRoutesRepository

    init(repo: PurposeRoutesRepository = PurposeRoutesRepository()) {
        self.repo = repo
    }

    private static func key(_ purpose: Purpose, _ passports: [String]) -> String {
        "\(purpose.rawValue)|\(PurposeRoutesRepository.parsePassports(passports).joined(separator: ","))"
    }

    /// Load the routes for `purpose` (nothing for travel).
    func load(purpose: Purpose, passports: [String]) async {
        guard purpose.isRoute else {
            current = nil
            wantedKey = nil
            return
        }
        let key = Self.key(purpose, passports)
        wantedKey = key
        if let hit = cache[key] {
            current = hit
            failed = false
            return
        }
        current = nil
        loading = true
        failed = false
        do {
            let routes = try await repo.routes(purpose: purpose, passports: passports)
            cache[key] = routes
            if wantedKey == key { current = routes }
        } catch {
            if wantedKey == key { failed = true }
        }
        if wantedKey == key { loading = false }
    }
}

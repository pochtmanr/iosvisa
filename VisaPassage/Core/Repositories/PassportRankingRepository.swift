import Foundation
import Observation
import Supabase

/// The passport ranking's data: the `passport_strength` view through PostgREST
/// (ranked on device by `DenseRank`), and the compare slices from the web's
/// anonymous `GET /api/passports?codes=`. Both go through `CatalogCache`
/// (24h, stale-while-revalidate), so the ranking opens instantly and offline.
struct PassportRankingRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared
    var baseURL: URL = AppConfig.webBaseURL
    var session: URLSession = .shared

    enum RepositoryError: Error {
        case http(Int)
    }

    /// Kept from IOS-02 so caches written before IOS-04 stay valid.
    static let strengthKey =
        "passport_strength:v1:passport_iso2,name,visa_free,visa_on_arrival,evisa,eta,visa_required,no_admission,known,mobility_score"

    static let maxCompare = 4

    static func compareKey(_ codes: [String]) -> String {
        "passports-compare:v1:\(normalize(codes).joined(separator: ","))"
    }

    /// Uppercased, deduped, sorted, at most four: the web route's own rule, so
    /// one selection is one cache entry and the response order is known.
    static func normalize(_ codes: [String]) -> [String] {
        Array(Array(Set(codes.map { $0.uppercased() }.filter { $0.count == 2 })).sorted().prefix(maxCompare))
    }

    /// The whole `passport_strength` view, in the web's order (`mobility_score`
    /// desc, then name), ready for `DenseRank.passportIndex`.
    func passportStrength(
        onRefresh: @escaping @Sendable ([PassportStrengthRow]) async -> Void = { _ in }
    ) async throws -> [PassportStrengthRow] {
        let client = client
        return try await cache.load(
            [PassportStrengthRow].self,
            key: Self.strengthKey,
            fetch: {
                try await client
                    .from("passport_strength")
                    .select("passport_iso2,name,visa_free,visa_on_arrival,evisa,eta,visa_required,no_admission,known,mobility_score")
                    .order("mobility_score", ascending: false)
                    .order("name", ascending: true)
                    .execute()
                    .value
            },
            onRefresh: onRefresh
        ).value
    }

    /// Requirement slices for 2–4 passports, in sorted-code order. Unknown codes
    /// are dropped by the server, as on the web.
    func compare(
        _ codes: [String],
        onRefresh: @escaping @Sendable ([ComparePassport]) async -> Void = { _ in }
    ) async throws -> [ComparePassport] {
        let codes = Self.normalize(codes)
        let url = Self.compareURL(base: baseURL, codes: codes)
        let session = session
        return try await cache.load(
            [ComparePassport].self,
            key: Self.compareKey(codes),
            fetch: {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw RepositoryError.http(status) }
                return try JSONDecoder.visaPassage.decode(CompareResponse.self, from: data).passports
            },
            onRefresh: onRefresh
        ).value
    }

    static func summaryKey(slug: String, locale: AppLocale) -> String {
        "passport-summary:v1:\(slug):\(locale.rawValue)"
    }

    /// The passport page's composed extras from `GET /api/passports/{slug}/summary`:
    /// the best second passports (`loadComboUplift` needs every passport's
    /// requirements, so it stays on the server) and the longest visa-free stays.
    func summary(
        slug: String,
        locale: AppLocale = .current,
        onRefresh: @escaping @Sendable (PassportSummary) async -> Void = { _ in }
    ) async throws -> PassportSummary {
        let url = Self.summaryURL(base: baseURL, slug: slug, locale: locale)
        let session = session
        return try await cache.load(
            PassportSummary.self,
            key: Self.summaryKey(slug: slug, locale: locale),
            fetch: {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw RepositoryError.http(status) }
                return try JSONDecoder.visaPassage.decode(PassportSummary.self, from: data)
            },
            onRefresh: onRefresh
        ).value
    }

    static func summaryURL(base: URL, slug: String, locale: AppLocale) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("api/passports/\(slug)/summary"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "locale", value: locale.rawValue)]
        return components.url!
    }

    static func compareURL(base: URL, codes: [String]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("api/passports"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "codes", value: normalize(codes).joined(separator: ","))]
        return components.url!
    }
}

// MARK: - Rows

/// One row of the `passport_strength` view (migration 0089). `mobility_score`
/// is visa-free + visa on arrival; never recompute it from the buckets.
struct PassportStrengthRow: Codable, Sendable, Hashable {
    var passportIso2: String
    var name: String
    var visaFree: Int
    var visaOnArrival: Int
    var evisa: Int
    var eta: Int
    var visaRequired: Int
    var noAdmission: Int
    var known: Int
    var mobilityScore: Int

    enum CodingKeys: String, CodingKey {
        case passportIso2 = "passport_iso2"
        case name
        case visaFree = "visa_free"
        case visaOnArrival = "visa_on_arrival"
        case evisa, eta
        case visaRequired = "visa_required"
        case noAdmission = "no_admission"
        case known
        case mobilityScore = "mobility_score"
    }
}

/// `GET /api/passports?codes=` body (web `ComparePassport`).
struct CompareResponse: Codable, Sendable {
    var passports: [ComparePassport]
}

struct ComparePassport: Codable, Sendable, Hashable {
    var iso2: String
    var name: String
    var rank: Int
    var mobilityScore: Int
    var requirements: [Requirement]

    struct Requirement: Codable, Sendable, Hashable {
        var destinationIso2: String
        var name: String
        var status: VisaStatus
        var daysAllowed: Int?

        enum CodingKeys: String, CodingKey {
            case destinationIso2 = "destination_iso2"
            case name, status
            case daysAllowed = "days_allowed"
        }
    }

    enum CodingKeys: String, CodingKey {
        case iso2, name, rank, requirements
        case mobilityScore = "mobility_score"
    }
}

/// `GET /api/passports/{slug}/summary` (web `PassportSummary`), minus the map
/// payload: the app draws its map from the cached requirements slice.
struct PassportSummary: Codable, Sendable, Hashable {
    var iso2: String
    var rank: Int
    var totalRanked: Int
    var mobilityScore: Int
    var topVisaFree: [Stay]
    var combos: [Combo]

    struct Stay: Codable, Sendable, Hashable {
        var iso2: String
        var name: String
        var daysAllowed: Int?

        enum CodingKeys: String, CodingKey {
            case iso2, name
            case daysAllowed = "days_allowed"
        }
    }

    /// A second passport and how many mobility destinations it adds (web `ComboUplift`).
    struct Combo: Codable, Sendable, Hashable, Identifiable {
        var iso2: String
        var name: String
        var uplift: Int
        var combinedMobility: Int

        var id: String { iso2 }

        enum CodingKeys: String, CodingKey {
            case iso2, name, uplift
            case combinedMobility = "combined_mobility"
        }
    }

    enum CodingKeys: String, CodingKey {
        case iso2, rank, totalRanked, topVisaFree, combos
        case mobilityScore = "mobility_score"
    }
}

// MARK: - Store

/// App-wide copy of the passport ranking (`passport_strength` + dense rank).
/// Home, Settings, the ranking and the passport page all read this one instance.
@MainActor
@Observable
final class PassportStrengthStore {
    private(set) var rows: [PassportStrengthRow] = []
    private(set) var loadFailed = false
    private let repo: PassportRankingRepository
    private var loaded = false

    /// The last index and what it was built from. Read from view bodies, so
    /// kept out of observation: rebuilding it must not invalidate views.
    @ObservationIgnored private var memo: (rows: Int, countries: Int, locale: AppLocale, index: [PassportIndexRow])?
    @ObservationIgnored private var version = 0

    init(repo: PassportRankingRepository = PassportRankingRepository()) {
        self.repo = repo
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await reload()
    }

    func reload() async {
        do {
            let fresh = try await repo.passportStrength { [weak self] fresh in
                await self?.setRows(fresh)
            }
            setRows(fresh)
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func setRows(_ fresh: [PassportStrengthRow]) {
        version += 1
        rows = fresh
    }

    /// The ranking for `countries` (the catalog supplies slugs, regions and
    /// localized names). Memoized until the rows, catalog or language change.
    func index(countries: [Country], locale: AppLocale = .current) -> [PassportIndexRow] {
        _ = rows // register observation of the rows
        if let memo, memo.rows == version, memo.countries == countries.count, memo.locale == locale {
            return memo.index
        }
        let index = DenseRank.passportIndex(rows, countries: countries, locale: locale)
        memo = (version, countries.count, locale, index)
        return index
    }

    func row(for iso2: String, countries: [Country]) -> PassportIndexRow? {
        let iso = iso2.uppercased()
        return index(countries: countries).first { $0.iso2 == iso }
    }

    /// Rank card numbers for one passport, or nil while loading or when it is unranked.
    func rank(for iso2: String, countries: [Country]) -> PassportRank? {
        let index = index(countries: countries)
        let iso = iso2.uppercased()
        return index.first { $0.iso2 == iso }.map { PassportRank($0, totalRanked: index.count) }
    }
}

import Foundation
import Observation
import Supabase

/// Cached reads of the public visa matrix for the Home passport card and the
/// Explore map and list: one passport's `visa_requirements` slice, and the
/// `passport_strength` view the ranking is built from. Both go through
/// `CatalogCache`, so they show instantly, work offline after the first load,
/// and refresh in the background after 24h.
struct RequirementsRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared

    static func requirementsKey(_ passport: String) -> String {
        "requirements:v1:\(passport.uppercased())"
    }

    static let strengthKey =
        "passport_strength:v1:passport_iso2,name,visa_free,visa_on_arrival,evisa,eta,visa_required,no_admission,known,mobility_score"

    /// Every `visa_requirements` row for one passport.
    func requirements(
        passport: String,
        onRefresh: @escaping @Sendable ([VisaRequirement]) async -> Void = { _ in }
    ) async throws -> [VisaRequirement] {
        let visa = VisaRepository(client: client)
        let iso = passport.uppercased()
        return try await cache.load(
            [VisaRequirement].self,
            key: Self.requirementsKey(iso),
            fetch: { try await visa.requirements(passport: iso) },
            onRefresh: onRefresh
        ).value
    }

    /// The whole `passport_strength` view, in the web's order (`mobility_score`
    /// desc, then name), ready for `PassportRanking.rank`.
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
}

// MARK: - Passport ranking

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

/// A passport's place in the ranking, as the web `/passports/[slug]` shows it.
struct PassportRank: Sendable, Equatable {
    var iso2: String
    var rank: Int
    var totalRanked: Int
    var mobilityScore: Int
    var visaFree: Int
    var known: Int
}

enum PassportRanking {
    /// Port of `loadPassportIndex` in `web/src/lib/passports/load-passport-strength.ts`.
    /// `rows` must already be ordered by `mobility_score` desc. Passports with no
    /// `countries.slug` have no profile page and take no rank; ties share a rank
    /// (dense ranking).
    static func rank(_ rows: [PassportStrengthRow], slugged: Set<String>) -> [String: PassportRank] {
        var ranks: [(row: PassportStrengthRow, rank: Int)] = []
        var rank = 0
        var previous: Int?
        for row in rows where slugged.contains(row.passportIso2.uppercased()) {
            if previous == nil || row.mobilityScore != previous {
                rank += 1
                previous = row.mobilityScore
            }
            ranks.append((row, rank))
        }
        var result: [String: PassportRank] = [:]
        for (row, rank) in ranks {
            result[row.passportIso2.uppercased()] = PassportRank(
                iso2: row.passportIso2.uppercased(),
                rank: rank,
                totalRanked: ranks.count,
                mobilityScore: row.mobilityScore,
                visaFree: row.visaFree,
                known: row.known
            )
        }
        return result
    }
}

// MARK: - Shared stores

/// App-wide requirements for the selected passports. Home and Explore read the
/// same instance, so the map, the list and the Home routes always agree.
@MainActor
@Observable
final class RequirementsStore {
    /// Rows per passport ISO2.
    private(set) var rowsByPassport: [String: [VisaRequirement]] = [:]
    /// Best row per destination across `passports` (status precedence, then
    /// the longer stay).
    private(set) var best: [String: VisaRequirement] = [:]
    private(set) var loading = false
    /// Set when a selected passport has no cached rows and the fetch failed.
    private(set) var failed = false

    private(set) var passports: [String] = []
    private let repo: RequirementsRepository

    init(repo: RequirementsRepository = RequirementsRepository()) {
        self.repo = repo
    }

    func status(for destination: String) -> VisaStatus {
        best[destination.uppercased()]?.status ?? .unknown
    }

    func row(for destination: String) -> VisaRequirement? {
        best[destination.uppercased()]
    }

    /// Load (cache first) every passport in `passports`, then fold.
    func load(_ passports: [String]) async {
        let wanted = passports.map { $0.uppercased() }
        self.passports = wanted
        recompute()
        let missing = wanted.filter { rowsByPassport[$0] == nil }
        guard !missing.isEmpty else { return }
        loading = true
        failed = false
        defer { loading = false }
        for iso in missing {
            do {
                let rows = try await repo.requirements(passport: iso) { [weak self] fresh in
                    await self?.apply(fresh, for: iso)
                }
                apply(rows, for: iso)
            } catch {
                failed = true
            }
        }
    }

    private func apply(_ rows: [VisaRequirement], for iso: String) {
        rowsByPassport[iso] = rows
        recompute()
    }

    private func recompute() {
        best = Self.fold(passports.flatMap { rowsByPassport[$0] ?? [] })
    }

    /// Best row per destination: the stronger status wins; on a tie, the longer stay.
    static func fold(_ rows: [VisaRequirement]) -> [String: VisaRequirement] {
        var result: [String: VisaRequirement] = [:]
        for row in rows {
            let key = row.destinationIso2.uppercased()
            guard let existing = result[key] else { result[key] = row; continue }
            let winner = VisaStatus.best(existing.status, row.status)
            if winner != existing.status {
                result[key] = row
            } else if row.status == existing.status, (row.daysAllowed ?? 0) > (existing.daysAllowed ?? 0) {
                result[key] = row
            }
        }
        return result
    }
}

/// App-wide copy of the passport ranking (`passport_strength` + dense rank).
@MainActor
@Observable
final class PassportStrengthStore {
    private(set) var rows: [PassportStrengthRow] = []
    private(set) var loadFailed = false
    private let repo: RequirementsRepository
    private var loaded = false

    init(repo: RequirementsRepository = RequirementsRepository()) {
        self.repo = repo
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        do {
            rows = try await repo.passportStrength { [weak self] fresh in
                await self?.setRows(fresh)
            }
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func setRows(_ fresh: [PassportStrengthRow]) { rows = fresh }

    /// Rank for one passport; `slugged` is the set of ISO2 codes with a `countries.slug`.
    func rank(for iso2: String, slugged: Set<String>) -> PassportRank? {
        PassportRanking.rank(rows, slugged: slugged)[iso2.uppercased()]
    }
}

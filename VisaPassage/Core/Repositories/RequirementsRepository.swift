import Foundation
import Observation
import Supabase

/// Cached reads of the public visa matrix for the Home passport card and the
/// Explore map and list, and the passport page: one passport's
/// `visa_requirements` slice, through `CatalogCache`, so it shows instantly,
/// works offline after the first load, and refreshes in the background after
/// 24h. The ranking itself is `PassportRankingRepository`.
struct RequirementsRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared

    static func requirementsKey(_ passport: String) -> String {
        "requirements:v1:\(passport.uppercased())"
    }

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

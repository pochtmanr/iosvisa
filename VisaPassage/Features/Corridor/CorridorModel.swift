import Foundation
import Observation

/// Loads one corridor: the matrix verdict (from the shared requirements slice
/// when it is loaded, else one PostgREST row) and the destination's composed
/// routes for this passport (cached), then resolves them into a `Corridor`.
@MainActor
@Observable
final class CorridorModel {
    enum State {
        case loading
        case loaded(Corridor)
        /// No matrix row for the pair: the web 404s here ("never guess a verdict").
        case noAnswer
        case failed
    }

    private(set) var state: State = .loading
    let fromISO2: String
    let toISO2: String

    private let repo: CorridorRepository

    init(fromISO2: String, toISO2: String, repo: CorridorRepository = CorridorRepository()) {
        self.fromISO2 = fromISO2.uppercased()
        self.toISO2 = toISO2.uppercased()
        self.repo = repo
    }

    var corridor: Corridor? {
        if case .loaded(let corridor) = state { return corridor }
        return nil
    }

    func load(countries: CountryStore, requirements: RequirementsStore) async {
        if corridor == nil { state = .loading }
        await countries.loadIfNeeded()
        guard let from = countries.country(fromISO2), let to = countries.country(toISO2), let slug = to.slug else {
            state = .failed
            return
        }
        do {
            let cached = requirements.rowsByPassport[fromISO2]?.first { $0.destinationIso2.uppercased() == toISO2 }
            async let verdictFetch = Self.verdict(cached: cached, repo: repo, from: fromISO2, to: toISO2)
            let routes = try await repo.destinationRoutes(slug: slug, passports: [fromISO2]) { [weak self] fresh in
                await self?.refresh(with: fresh)
            }
            guard let verdict = try await verdictFetch else {
                state = .noAnswer
                return
            }
            state = .loaded(Corridor(from: from, to: to, verdict: verdict, routes: routes))
        } catch {
            if corridor == nil { state = .failed }
        }
    }

    private nonisolated static func verdict(
        cached: VisaRequirement?,
        repo: CorridorRepository,
        from: String,
        to: String
    ) async throws -> VisaRequirement? {
        if let cached { return cached }
        return try await repo.requirement(passport: from, destination: to)
    }

    private func refresh(with routes: DestinationRoutesView) {
        guard let current = corridor else { return }
        state = .loaded(Corridor(from: current.from, to: current.to, verdict: current.verdict, routes: routes))
    }
}

import Foundation
import Observation

/// App-wide cache of the public `countries` catalog, loaded once and shared with
/// every country picker via the environment.
@MainActor
@Observable
final class CountryStore {
    private(set) var countries: [Country] = []

    private let repo = CountryRepository()
    private var loaded = false

    /// Load the catalog once. Safe to call from multiple screens.
    func loadIfNeeded() async {
        guard !loaded else { return }
        do {
            countries = try await repo.all()
            loaded = true
        } catch {
            // Leave empty; pickers fall back to showing raw codes.
        }
    }

    func country(_ iso2: String?) -> Country? {
        guard let iso2, !iso2.isEmpty else { return nil }
        return countries.first { $0.iso2.caseInsensitiveCompare(iso2) == .orderedSame }
    }

    /// Display name for a code, falling back to the raw (uppercased) code.
    func name(forISO2 iso2: String?) -> String? {
        guard let iso2, !iso2.isEmpty else { return nil }
        return country(iso2)?.name ?? iso2.uppercased()
    }
}

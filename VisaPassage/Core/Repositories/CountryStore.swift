import Foundation
import Observation

/// App-wide copy of the public `countries` catalog, shared with every country
/// picker and the map via the environment. Served from `CatalogCache`: a
/// cached list shows instantly (also offline) and refreshes in the background
/// once it is older than 24h.
@MainActor
@Observable
final class CountryStore {
    private(set) var countries: [Country] = []
    /// Set when there is nothing cached and the network fetch failed.
    private(set) var loadFailed = false

    /// Bump when the selected columns change, so old cache files are ignored.
    static let cacheKey = "countries:v1:iso2,name,region,flag_emoji,is_passport,iso_numeric,slug,coverage_tier,translations"

    private let repo: CountryRepository
    private let cache: CatalogCache
    private var loaded = false

    init(repo: CountryRepository = CountryRepository(), cache: CatalogCache = .shared) {
        self.repo = repo
        self.cache = cache
    }

    /// Load the catalog once. Safe to call from multiple screens.
    func loadIfNeeded() async {
        guard !loaded else { return }
        let repo = repo
        do {
            let result = try await cache.load(
                [Country].self,
                key: Self.cacheKey,
                fetch: { try await repo.all() },
                onRefresh: { [weak self] fresh in await self?.apply(fresh) }
            )
            apply(result.value)
            loaded = true
        } catch {
            // Leave empty; pickers fall back to showing raw codes.
            loadFailed = true
        }
    }

    private func apply(_ list: [Country]) {
        let locale = AppLocale.current
        countries = list.sorted {
            $0.localizedName(in: locale).localizedStandardCompare($1.localizedName(in: locale)) == .orderedAscending
        }
        loadFailed = false
    }

    func country(_ iso2: String?) -> Country? {
        guard let iso2, !iso2.isEmpty else { return nil }
        return countries.first { $0.iso2.caseInsensitiveCompare(iso2) == .orderedSame }
    }

    /// Display name for a code in the app's language, falling back to the raw
    /// (uppercased) code.
    func name(forISO2 iso2: String?) -> String? {
        guard let iso2, !iso2.isEmpty else { return nil }
        return country(iso2)?.displayName ?? iso2.uppercased()
    }
}

import Foundation
import Supabase

/// Everything about one destination, composed by the web: every purpose group,
/// product, availability note and document checklist, personalised for the
/// given passports and already localized (`GET /api/destinations/{slug}`).
///
/// Why this route and not the prompt's two: `/api/visa-checker/pair` sits
/// behind Vercel BotID and answers a native client with 403, and
/// `/api/travel-checklist` returns a PDF. This one is anonymous, unguarded JSON.
/// It is slow (about 2.5s cold, about 130 KB), so every read goes through
/// `CatalogCache` (24h, stale-while-revalidate).
struct CorridorRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared
    var baseURL: URL = AppConfig.webBaseURL
    var session: URLSession = .shared

    enum RepositoryError: Error {
        case http(Int)
        case notFound
    }

    static func routesKey(slug: String, passports: [String], locale: AppLocale) -> String {
        "destination-routes:v1:\(slug.lowercased()):\(normalize(passports).joined(separator: ",")):\(locale.rawValue)"
    }

    /// Uppercased, deduped, sorted: one passport set is one cache entry.
    static func normalize(_ passports: [String]) -> [String] {
        Array(Set(passports.map { $0.uppercased() }.filter { $0.count == 2 })).sorted()
    }

    func destinationRoutes(
        slug: String,
        passports: [String],
        locale: AppLocale = .current,
        onRefresh: @escaping @Sendable (DestinationRoutesView) async -> Void = { _ in }
    ) async throws -> DestinationRoutesView {
        let codes = Self.normalize(passports)
        let fetch = fetcher(slug: slug, passports: codes, locale: locale)
        return try await cache.load(
            DestinationRoutesView.self,
            key: Self.routesKey(slug: slug, passports: codes, locale: locale),
            fetch: fetch,
            onRefresh: onRefresh
        ).value
    }

    private func fetcher(
        slug: String,
        passports: [String],
        locale: AppLocale
    ) -> @Sendable () async throws -> DestinationRoutesView {
        let url = Self.routesURL(base: baseURL, slug: slug, passports: passports, locale: locale)
        let session = session
        return {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw RepositoryError.notFound }
            guard (200..<300).contains(status) else { throw RepositoryError.http(status) }
            return try JSONDecoder.visaPassage.decode(DestinationRoutesView.self, from: data)
        }
    }

    static func routesURL(base: URL, slug: String, passports: [String], locale: AppLocale) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("api/destinations/\(slug.lowercased())"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "passports", value: passports.joined(separator: ",")),
            URLQueryItem(name: "locale", value: locale.rawValue),
        ]
        return components.url!
    }

    /// The matrix row for one pair, when the requirements slice isn't loaded.
    func requirement(passport: String, destination: String) async throws -> VisaRequirement? {
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

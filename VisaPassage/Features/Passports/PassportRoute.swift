import SwiftUI

/// Typed navigation for the Passports screens, pushed from Explore (toolbar),
/// Home (the passport card) and deep links (`/passports/{slug}`).
enum PassportRoute: Hashable {
    /// `/passports`.
    case ranking
    /// `/passports/{slug}`, by ISO2.
    case detail(String)
    /// `/passports/compare?with=…`: 0–4 ISO2 codes to start from.
    case compare([String])
}

extension View {
    /// Registers the Passports screens on the enclosing `NavigationStack`.
    func passportDestinations() -> some View {
        navigationDestination(for: PassportRoute.self) { route in
            switch route {
            case .ranking: PassportRankingView()
            case let .detail(iso2): PassportDetailView(iso2: iso2)
            case let .compare(codes): PassportCompareView(initialCodes: codes)
            }
        }
    }
}

extension AppLocale {
    /// `https://visapassage.com/{locale}/passports/{slug}` (no prefix for English, as on the site).
    func passportURL(slug: String?) -> URL {
        guard let slug else { return webURL(path: "/passports") }
        return webURL(path: "/passports/\(slug)")
    }
}

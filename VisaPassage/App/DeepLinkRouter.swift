import Foundation
import Observation

/// Parses incoming universal links, custom-scheme URLs and Spotlight item ids
/// into typed routes the app can act on: OAuth/magic-link callbacks, the visa
/// checker, and the visapassage.com pages the AASA file claims (`/travel/*`,
/// `/passports/*`, `/destinations/*`, `/app/trackers/*`, each with or without
/// a locale prefix).
@MainActor
@Observable
final class DeepLinkRouter {
    enum Route: Equatable {
        case authCallback(URL)              // OAuth code / magic-link token
        case visaChecker(passports: [String], destination: String?)
        /// `/travel/{from}/{to}`: country slugs (or ISO2 from Spotlight).
        case corridor(from: String, to: String)
        /// `/passports/{slug}`.
        case passport(String)
        /// `/destinations/{slug}`.
        case destination(String)
        /// `/app/trackers` or `/app/trackers/{id}`.
        case tracker(id: String?)
        case unknown(URL)
    }

    /// Most recent route, consumed by the relevant view.
    private(set) var pending: Route?

    func handle(_ url: URL) {
        pending = Self.parse(url)
    }

    /// A Core Spotlight item id (`corridor:US-DE`, `passport:US`).
    func handleSpotlight(identifier: String) {
        if let route = Self.parse(spotlightIdentifier: identifier) { pending = route }
    }

    func consume() { pending = nil }

    nonisolated static func parse(_ url: URL) -> Route {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path

        // Supabase auth callbacks carry `code` or `token_hash`.
        if let items = components?.queryItems,
           items.contains(where: { $0.name == "code" || $0.name == "token_hash" }) {
            return .authCallback(url)
        }

        // Universal links: https://visapassage.com/[ru/]travel/…
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
           let host = url.host?.lowercased(),
           host == AppConfig.universalLinkHost || host == "www.\(AppConfig.universalLinkHost)" {
            if let route = webRoute(path) { return route }
            return .unknown(url)
        }

        // Discovery deep link: visapassage://visa-checker?passports=US,CA&to=DE
        // (host or path may carry "visa-checker", or just the query params).
        let items = components?.queryItems ?? []
        let passportsRaw = items.first { $0.name == "passports" }?.value
        let toRaw = items.first { $0.name == "to" }?.value
        let mentionsChecker = (url.host?.contains("visa-checker") ?? false)
            || path.contains("visa-checker")
        if mentionsChecker || passportsRaw != nil || toRaw != nil {
            let passports = (passportsRaw ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { $0.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil }
            let destination = toRaw?.trimmingCharacters(in: .whitespaces).uppercased()
            let cleanDestination = (destination?.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil)
                ? destination : nil
            if !passports.isEmpty || cleanDestination != nil {
                return .visaChecker(passports: passports, destination: cleanDestination)
            }
        }

        return .unknown(url)
    }

    /// Map a site path to a route. A leading locale segment (`en`, `ru`) is
    /// dropped, so `/ru/travel/a/b` and `/travel/a/b` are the same route.
    nonisolated static func webRoute(_ path: String) -> Route? {
        var parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if let first = parts.first, AppLocale(rawValue: first.lowercased()) != nil {
            parts.removeFirst()
        }
        switch parts.count {
        case 3 where parts[0] == "travel":
            return .corridor(from: parts[1].lowercased(), to: parts[2].lowercased())
        case 2 where parts[0] == "passports" && parts[1] != "compare":
            return .passport(parts[1].lowercased())
        case 2 where parts[0] == "destinations":
            return .destination(parts[1].lowercased())
        case 2 where parts[0] == "app" && parts[1] == "trackers":
            return .tracker(id: nil)
        case 3... where parts[0] == "app" && parts[1] == "trackers":
            return .tracker(id: parts[2] == "new" ? nil : parts[2])
        default:
            return nil
        }
    }

    nonisolated static func parse(spotlightIdentifier id: String) -> Route? {
        let pieces = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return nil }
        switch pieces[0] {
        case "corridor":
            let codes = pieces[1].split(separator: "-").map(String.init)
            guard codes.count == 2 else { return nil }
            return .corridor(from: codes[0], to: codes[1])
        case "passport":
            return .passport(pieces[1])
        default:
            return nil
        }
    }
}

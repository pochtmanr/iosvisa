import Foundation
import Observation

/// Parses incoming universal links and custom-scheme URLs into typed routes the
/// app can act on: OAuth/magic-link callbacks, Revolut checkout returns, and
/// in-app navigation (e.g. opening a specific application).
@MainActor
@Observable
final class DeepLinkRouter {
    enum Route: Equatable {
        case authCallback(URL)              // OAuth code / magic-link token
        case checkoutReturn(orderID: String)
        case application(id: String)
        case visaChecker(passports: [String], destination: String?)
        case unknown(URL)
    }

    /// Most recent route, consumed by the relevant view.
    private(set) var pending: Route?

    func handle(_ url: URL) {
        pending = parse(url)
    }

    func consume() { pending = nil }

    private func parse(_ url: URL) -> Route {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path

        // Supabase auth callbacks carry `code` or `token_hash`.
        if let items = components?.queryItems,
           items.contains(where: { $0.name == "code" || $0.name == "token_hash" }) {
            return .authCallback(url)
        }

        if path.contains("/checkout/return") || path.contains("checkout") {
            let order = components?.queryItems?.first(where: { $0.name == "order" })?.value
            if let order { return .checkoutReturn(orderID: order) }
        }

        if let range = path.range(of: "/applications/") {
            let id = String(path[range.upperBound...]).split(separator: "/").first.map(String.init)
            if let id { return .application(id: id) }
        }

        // Discovery deep link: visapilot://visa-checker?passports=US,CA&to=DE
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
}

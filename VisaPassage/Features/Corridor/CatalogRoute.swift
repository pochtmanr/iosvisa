import SwiftUI

/// Typed navigation for the catalog screens, so they can be pushed from any
/// stack (Explore today, Home and deep links later) with one destination
/// table. Product and document values travel whole: the screens behind them
/// never refetch what the corridor or destination already loaded.
enum CatalogRoute: Hashable {
    /// `/travel/{from}/{to}`.
    case corridor(from: String, to: String)
    /// `/destinations/{slug}`, by ISO2.
    case destination(String)
    case product(ProductContext)
    case checklist(ProductContext)
    case guide(GuideContext)
}

/// One visa product as reached from a corridor or a destination.
struct ProductContext: Hashable {
    var product: RouteProduct
    var visaTypeName: String?
    var destination: Country
    /// The passport the product was resolved for, when there is one.
    var passport: String?
    var passportStatus: VisitorStatus?
    var eligibility: [RoutePassportEligibility] = []

    /// `/destinations/{slug}#visa-{id}`: the web shows a product as a card there.
    var webURL: URL? {
        guard let slug = destination.slug else { return nil }
        return AppLocale.current.webURL(path: "/destinations/\(slug)#visa-\(product.id.uuidString.lowercased())")
    }
}

/// One checklist document, with the passport whose guides apply.
struct GuideContext: Hashable {
    var requirement: DocumentRequirement
    var passport: String?
}

extension View {
    /// Registers the catalog screens on the enclosing `NavigationStack`.
    func catalogDestinations() -> some View {
        navigationDestination(for: CatalogRoute.self) { route in
            switch route {
            case let .corridor(from, to): CorridorView(fromISO2: from, toISO2: to)
            case let .destination(iso2): DestinationDetailView(destinationISO2: iso2)
            case let .product(context): VisaProductView(context: context)
            case let .checklist(context): ChecklistView(context: context)
            case let .guide(context): DocumentGuideView(context: context)
            }
        }
    }
}

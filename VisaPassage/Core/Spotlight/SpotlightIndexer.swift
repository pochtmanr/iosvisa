import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes the corridors and passports a user has viewed into Core Spotlight,
/// so "Spain visa" in system search opens the app on that page. Item ids are
/// what `DeepLinkRouter.parse(spotlightIdentifier:)` reads back:
/// `corridor:US-ES`, `passport:US`.
enum SpotlightIndexer {
    static let domain = "com.visapassage.viewed"

    static func corridorID(from: String, to: String) -> String {
        "corridor:\(from.uppercased())-\(to.uppercased())"
    }

    static func passportID(_ iso2: String) -> String { "passport:\(iso2.uppercased())" }

    /// A passport × destination the user opened.
    static func indexCorridor(from: String, fromName: String, to: String, toName: String,
                              status: String?, url: URL) {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = String(localized: "\(fromName) → \(toName)")
        attributes.contentDescription = status.map {
            String(localized: "\(toName) for \(fromName) passport holders: \($0)")
        } ?? String(localized: "Visa options for \(fromName) passport holders travelling to \(toName)")
        attributes.keywords = [toName, fromName, String(localized: "visa")]
        attributes.contentURL = url
        index(id: corridorID(from: from, to: to), attributes: attributes)
    }

    /// A passport whose rank the user looked at or shared.
    static func indexPassport(_ iso2: String, name: String, rank: Int?, url: URL) {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = String(localized: "\(name) passport")
        if let rank {
            attributes.contentDescription = String(localized: "Ranked #\(rank) by visa-free access")
        }
        attributes.keywords = [name, String(localized: "passport")]
        attributes.contentURL = url
        index(id: passportID(iso2), attributes: attributes)
    }

    /// Clears everything (sign-out or account deletion).
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }

    private static func index(id: String, attributes: CSSearchableItemAttributeSet) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = Calendar.current.date(byAdding: .day, value: 90, to: .now)
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }
}

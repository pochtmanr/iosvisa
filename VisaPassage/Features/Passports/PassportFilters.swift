import Foundation

/// Search, region filter and the "longest visa-free stays" pick, ported from
/// the web `/passports` leaderboard (`_components/search.ts`,
/// `PassportLeaderboard.tsx`) and `GET /api/passports/[slug]/summary`.
enum PassportFilters {
    /// The web's continent buckets, in its chip order.
    static let regions = ["Africa", "Americas", "Asia", "Europe", "Oceania"]

    /// Only the regions some ranked passport belongs to (web `regions`).
    static func regions(in rows: [PassportIndexRow]) -> [String] {
        let present = Set(rows.compactMap(\.region))
        return regions.filter(present.contains)
    }

    static func regionTitle(_ region: String) -> String {
        switch region {
        case "Africa": return String(localized: "Africa")
        case "Americas": return String(localized: "Americas")
        case "Asia": return String(localized: "Asia")
        case "Europe": return String(localized: "Europe")
        case "Oceania": return String(localized: "Oceania")
        default: return region
        }
    }

    /// Case- and accent-insensitive key ("Côte" matches "cote"), as `searchKey` on the web.
    static func searchKey(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Web `matchesQuery`: the name contains the query, or the query is the ISO2
    /// code. The English name also matches, so "Germany" finds "Германия".
    static func matches(_ row: PassportIndexRow, query: String) -> Bool {
        let key = searchKey(query)
        guard !key.isEmpty else { return true }
        return searchKey(row.name).contains(key)
            || searchKey(row.englishName).contains(key)
            || row.iso2.lowercased() == key
    }

    /// The ranking rows for a region (nil = all) and a query, still in rank order.
    static func filter(_ rows: [PassportIndexRow], region: String?, query: String) -> [PassportIndexRow] {
        rows.filter { (region == nil || $0.region == region) && matches($0, query: query) }
    }

    /// How many destinations the passport page lists.
    static let topVisaFreeLimit = 24

    /// One visa-free destination on the passport page.
    struct Stay: Identifiable, Hashable, Sendable {
        var iso2: String
        var name: String
        var daysAllowed: Int?
        var id: String { iso2 }
    }

    /// The summary route's rule: visa-free only, longest stay first, then A–Z, top 24.
    static func topVisaFree(
        _ rows: [VisaRequirement],
        name: (String) -> String?,
        limit: Int = topVisaFreeLimit
    ) -> [Stay] {
        let stays: [Stay] = rows.compactMap { row in
            guard row.status == .visaFree else { return nil }
            let iso = row.destinationIso2.uppercased()
            // The web drops destinations missing from `countries`.
            guard let label = name(iso) else { return nil }
            return Stay(iso2: iso, name: label, daysAllowed: row.daysAllowed)
        }
        return Array(stays.sorted {
            let a = $0.daysAllowed ?? 0, b = $1.daysAllowed ?? 0
            if a != b { return a > b }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }.prefix(limit))
    }
}

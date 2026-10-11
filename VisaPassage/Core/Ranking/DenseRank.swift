import Foundation

/// Destinations per entry status for one passport, straight from the
/// `passport_strength` view buckets (web `PassportCounts`).
struct PassportCounts: Codable, Sendable, Hashable {
    var visaFree: Int
    var visaOnArrival: Int
    var evisa: Int
    var eta: Int
    var visaRequired: Int
    var noAdmission: Int

    /// The statuses a passport page breaks down, in the web's `PRECEDENCE` order.
    static let statuses: [VisaStatus] = [.visaFree, .visaOnArrival, .evisa, .eta, .visaRequired, .noAdmission]

    subscript(status: VisaStatus) -> Int {
        switch status {
        case .visaFree: return visaFree
        case .visaOnArrival: return visaOnArrival
        case .evisa: return evisa
        case .eta: return eta
        case .visaRequired: return visaRequired
        case .noAdmission: return noAdmission
        case .unknown: return 0
        }
    }

    var total: Int { visaFree + visaOnArrival + evisa + eta + visaRequired + noAdmission }
}

/// One ranked passport (web `PassportIndexRow`).
struct PassportIndexRow: Codable, Sendable, Hashable, Identifiable {
    var iso2: String
    /// Localized from `countries.translations`, falling back to the view's name.
    var name: String
    /// Unlocalized `countries.name`, so search also finds "Germany" in Russian.
    var englishName: String
    var slug: String
    /// Continent bucket from `countries.region` (Africa, Americas, Asia, Europe, Oceania).
    var region: String?
    /// Dense rank by `mobility_score` (ties share a rank).
    var rank: Int
    var mobilityScore: Int
    var known: Int
    var counts: PassportCounts

    var id: String { iso2 }
    var visaFree: Int { counts.visaFree }
}

/// Port of `loadPassportIndex` in `web/src/lib/passports/load-passport-strength.ts`.
/// The rank is computed here once; every screen (Home card, ranking, passport
/// page, share card) reads it back, never recomputing it elsewhere.
enum DenseRank {
    /// The ranking from `passport_strength` rows **already ordered** by
    /// `mobility_score` desc, then name (the PostgREST query's order, same as
    /// the web). Exclusions match the web: a passport with no `countries.slug`
    /// has no profile page and takes no rank. Ties share a rank, and the next
    /// distinct score takes the next number (dense: 1, 1, 2).
    static func passportIndex(
        _ rows: [PassportStrengthRow],
        countries: [Country],
        locale: AppLocale = .current
    ) -> [PassportIndexRow] {
        var byISO: [String: Country] = [:]
        for country in countries { byISO[country.iso2.uppercased()] = country }

        var index: [PassportIndexRow] = []
        index.reserveCapacity(rows.count)
        var rank = 0
        var previous: Int?
        for row in rows {
            let iso = row.passportIso2.uppercased()
            let country = byISO[iso]
            guard let slug = country?.slug, !slug.isEmpty else { continue }
            if previous == nil || row.mobilityScore != previous {
                rank += 1
                previous = row.mobilityScore
            }
            index.append(PassportIndexRow(
                iso2: iso,
                name: country?.localizedName(in: locale) ?? row.name,
                englishName: country?.name ?? row.name,
                slug: slug,
                region: country?.region,
                rank: rank,
                mobilityScore: row.mobilityScore,
                known: row.known,
                counts: PassportCounts(
                    visaFree: row.visaFree,
                    visaOnArrival: row.visaOnArrival,
                    evisa: row.evisa,
                    eta: row.eta,
                    visaRequired: row.visaRequired,
                    noAdmission: row.noAdmission
                )
            ))
        }
        return index
    }
}

/// A passport's place in the ranking, as the Home card, Settings and the
/// share card show it.
struct PassportRank: Sendable, Equatable {
    var iso2: String
    var rank: Int
    var totalRanked: Int
    var mobilityScore: Int
    var visaFree: Int
    var known: Int

    init(iso2: String, rank: Int, totalRanked: Int, mobilityScore: Int, visaFree: Int, known: Int) {
        self.iso2 = iso2
        self.rank = rank
        self.totalRanked = totalRanked
        self.mobilityScore = mobilityScore
        self.visaFree = visaFree
        self.known = known
    }

    init(_ row: PassportIndexRow, totalRanked: Int) {
        iso2 = row.iso2
        rank = row.rank
        self.totalRanked = totalRanked
        mobilityScore = row.mobilityScore
        visaFree = row.visaFree
        known = row.known
    }
}

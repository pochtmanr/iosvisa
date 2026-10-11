import Foundation

/// 2–4 passports side by side, from `GET /api/passports?codes=`. Ports the web
/// `/passports/compare` client: `mergeRequirements` (`web/src/lib/passports/merge.ts`)
/// for the combined reach, its summary (combined mobility, best single
/// passport, leads per passport), and the pair page's "where they differ".
struct PassportComparison: Sendable {
    /// One destination in the combined view.
    struct Merged: Hashable, Sendable {
        var destinationIso2: String
        var status: VisaStatus
        var daysAllowed: Int?
        /// The passport that carries the status; on a tie, the first in code order.
        var viaPassport: String
    }

    /// A destination whose status is not the same for every passport.
    struct DiffRow: Identifiable, Hashable, Sendable {
        var iso2: String
        var name: String
        /// One status per passport, in `passports` order.
        var statuses: [VisaStatus]
        var best: VisaStatus
        var id: String { iso2 }
    }

    let passports: [ComparePassport]
    let merged: [Merged]
    /// Combined destinations per status.
    let counts: [VisaStatus: Int]
    /// Destinations visa-free or on arrival with at least one passport.
    let combinedMobility: Int
    /// The strongest single passport's mobility score.
    let bestSingle: Int
    /// Mobility destinations each passport carries in the combined view.
    let leads: [String: Int]
    /// Destinations with data for every passport where the statuses differ,
    /// easiest best status first, then A–Z.
    let differing: [DiffRow]
    /// Destinations with data for every passport and the same status for all.
    let sameCount: Int

    static let mobility: Set<VisaStatus> = [.visaFree, .visaOnArrival]

    /// `passports` must be in the API's order (sorted codes): it decides ties.
    /// `name` localizes a destination ISO2, falling back to the API's English name.
    init(_ passports: [ComparePassport], name: (String) -> String? = { _ in nil }) {
        self.passports = passports
        merged = Self.merge(passports)

        var counts: [VisaStatus: Int] = [:]
        var leads: [String: Int] = [:]
        var combined = 0
        for m in merged {
            counts[m.status, default: 0] += 1
            if Self.mobility.contains(m.status) {
                combined += 1
                leads[m.viaPassport, default: 0] += 1
            }
        }
        self.counts = counts
        self.leads = leads
        combinedMobility = combined
        bestSingle = passports.map(\.mobilityScore).max() ?? 0

        // Like for like: only destinations every passport has a row for.
        var perDestination: [String: [VisaStatus?]] = [:]
        var englishName: [String: String] = [:]
        var order: [String] = []
        for (i, passport) in passports.enumerated() {
            for r in passport.requirements {
                let iso = r.destinationIso2.uppercased()
                if perDestination[iso] == nil {
                    perDestination[iso] = Array(repeating: nil, count: passports.count)
                    englishName[iso] = r.name
                    order.append(iso)
                }
                perDestination[iso]?[i] = r.status
            }
        }
        var differing: [DiffRow] = []
        var same = 0
        for iso in order {
            let statuses = (perDestination[iso] ?? []).compactMap { $0 }
            guard statuses.count == passports.count, !statuses.isEmpty else { continue }
            if Set(statuses).count == 1 {
                same += 1
                continue
            }
            let best = statuses.dropFirst().reduce(statuses[0]) { VisaStatus.best($0, $1) }
            differing.append(DiffRow(
                iso2: iso,
                name: name(iso) ?? englishName[iso] ?? iso,
                statuses: statuses,
                best: best
            ))
        }
        let precedence = VisaStatus.precedence
        differing.sort {
            let a = precedence.firstIndex(of: $0.best) ?? precedence.count
            let b = precedence.firstIndex(of: $1.best) ?? precedence.count
            if a != b { return a < b }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
        self.differing = differing
        sameCount = same
    }

    /// Port of `mergeRequirements`: one row per destination, the least-friction
    /// status wins, and on a tie the first-seen passport keeps it. Output is in
    /// first-seen destination order. Do not change the tie or order semantics.
    static func merge(_ passports: [ComparePassport]) -> [Merged] {
        var merged: [String: Merged] = [:]
        var order: [String] = []
        for passport in passports {
            for row in passport.requirements {
                let key = row.destinationIso2
                guard let existing = merged[key] else {
                    merged[key] = Merged(destinationIso2: key, status: row.status,
                                         daysAllowed: row.daysAllowed, viaPassport: passport.iso2)
                    order.append(key)
                    continue
                }
                if VisaStatus.best(existing.status, row.status) != existing.status {
                    merged[key] = Merged(destinationIso2: key, status: row.status,
                                         daysAllowed: row.daysAllowed, viaPassport: passport.iso2)
                }
            }
        }
        return order.compactMap { merged[$0] }
    }
}

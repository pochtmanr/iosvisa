import Foundation

/// Pure reducers for combining visa status across multiple passports. Mirrors
/// the web `PRECEDENCE` / `bestStatus` logic in `web/src/lib/visa-status.ts`.
/// Headless and side-effect-free → fully unit-testable.
extension VisaStatus {
    /// Best-to-worst ordering. Lower index = stronger access (less friction).
    /// `.unknown` is treated as the weakest known regime.
    static let precedence: [VisaStatus] = [
        .visaFree, .visaOnArrival, .evisa, .visaRequired, .noAdmission, .unknown,
    ]

    private var rank: Int {
        VisaStatus.precedence.firstIndex(of: self) ?? VisaStatus.precedence.count
    }

    /// The stronger of two statuses (the one a traveller would prefer).
    static func best(_ a: VisaStatus, _ b: VisaStatus) -> VisaStatus {
        a.rank <= b.rank ? a : b
    }

    /// Collapse many requirement rows (potentially from several passports) into
    /// the single best status per destination ISO2. Used to shade the map and
    /// the destinations grid when more than one passport is selected.
    static func bestByDestination(_ rows: [VisaRequirement]) -> [String: VisaStatus] {
        var result: [String: VisaStatus] = [:]
        for row in rows {
            let key = row.destinationIso2.uppercased()
            if let existing = result[key] {
                result[key] = best(existing, row.status)
            } else {
                result[key] = row.status
            }
        }
        return result
    }
}

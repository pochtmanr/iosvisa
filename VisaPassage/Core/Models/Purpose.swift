import Foundation

// Swift port of `web/src/lib/checker/purposes.ts`: the purpose axis of the
// landing checker and the dashboard's purpose cards. `travel` is the
// passport → entry-status map (`visa_requirements`); every other purpose paints
// the destinations that publish at least one route of its legacy
// `visa_types.code`s (`visa_products`, labelled Unverified in the UI).

/// The seven purposes, in the web's `PURPOSE_ORDER`.
enum Purpose: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case travel, study, work, remote, immigrate, invest, family

    var id: Self { self }

    /// Every purpose but travel paints routes instead of entry status.
    var isRoute: Bool { self != .travel }

    /// Legacy `visa_types.code`s in this purpose, in display order (`ROUTE_PURPOSES`).
    var typeCodes: [String] {
        switch self {
        case .travel: return []
        case .study: return ["student", "language_study", "exchange_program", "internship_trainee"]
        case .work: return ["skilled_work", "talent", "working_holiday", "seasonal_work",
                            "intra_company_transfer", "religious_worker", "journalist_media"]
        case .remote: return ["digital_nomad", "freelancer", "self_employment", "startup_entrepreneur"]
        case .immigrate: return ["permanent_residence", "long_term_residence", "retirement",
                                 "non_lucrative", "ancestry_repatriation"]
        case .invest: return ["golden_visa", "residence_by_property", "business_investor",
                              "citizenship_by_investment"]
        case .family: return ["family_reunification", "spouse_partner", "dependent_relative"]
        }
    }

    /// `marketing.visaChecker.purpose.*`.
    var title: String {
        switch self {
        case .travel: return String(localized: "purpose.travel", defaultValue: "Travel")
        case .study: return String(localized: "purpose.study", defaultValue: "Study")
        case .work: return String(localized: "purpose.work", defaultValue: "Work")
        case .remote: return String(localized: "purpose.remote", defaultValue: "Remote work")
        case .immigrate: return String(localized: "purpose.immigrate", defaultValue: "Move abroad")
        case .invest: return String(localized: "purpose.invest", defaultValue: "Invest")
        case .family: return String(localized: "purpose.family", defaultValue: "Family")
        }
    }

    /// `marketing.visaChecker.stage.purposeShort.*`.
    var short: String {
        switch self {
        case .travel: return String(localized: "Tourism, business trips and transit")
        case .study: return String(localized: "Degrees, language courses and exchanges")
        case .work: return String(localized: "Jobs, talent and working-holiday routes")
        case .remote: return String(localized: "Digital nomad and freelance routes")
        case .immigrate: return String(localized: "Long-term and permanent residence")
        case .invest: return String(localized: "Golden visas and investor routes")
        case .family: return String(localized: "Join a spouse, partner or relative")
        }
    }

    /// Onboarding goals (`profiles.goal`, migration 0036) → the purpose (`GOAL_PURPOSE`).
    private static let goalPurpose: [String: Purpose] = [
        "travel": .travel,
        "study": .study,
        "work_abroad": .work,
        "immigrate": .immigrate,
        "invest": .invest,
    ]

    /// The purpose the account said it cares about first, if any (`purposeFromGoals`).
    static func fromGoals(_ goals: [String]?) -> Purpose? {
        for goal in goals ?? [] {
            if let purpose = goalPurpose[goal] { return purpose }
        }
        return nil
    }
}

/// One route as the web checker's API returns it (`CheckerRoute`).
struct CheckerRoute: Sendable, Hashable, Identifiable {
    /// `visa_products.id`.
    let id: UUID
    let code: String
    let name: String
    let visaTypeCode: String
    let maxStayDays: Int?
    let processingTimeDays: Int?
    /// Per-passport override when one exists, else the product default.
    let eligibility: VisaEligibility
    /// Rights the route grants beyond its purpose, free-text notes dropped.
    let rights: [CheckerRouteRight]
}

/// A granted right (`CheckerRouteRight`): `work` may carry hours per week,
/// `residency` the years to residency.
struct CheckerRouteRight: Sendable, Hashable {
    enum Key: String, Sendable { case work, study, residency, family }
    let key: Key
    var hours: Int? = nil
    var years: Int? = nil

    /// `parseRights` (`web/src/components/destinations/RightsChips.tsx`): the
    /// granted rights in display order; denied ones (`false`, `{allowed:false}`)
    /// are skipped.
    static func parse(_ attributes: [String: JSONValue]) -> [CheckerRouteRight] {
        func allowed(_ value: JSONValue) -> Bool {
            if case .bool(false) = value { return false }
            if case .object(let o) = value, case .bool(false)? = o["allowed"] { return false }
            return true
        }
        func number(_ value: JSONValue, _ key: String) -> Int? {
            guard case .object(let o) = value, case .number(let n)? = o[key], n.isFinite, n != 0 else { return nil }
            return Int(n)
        }
        var out: [CheckerRouteRight] = []
        if let v = attributes["work_rights"], allowed(v) {
            out.append(.init(key: .work, hours: number(v, "hours_per_week")))
        }
        if let v = attributes["study_rights"], allowed(v) {
            out.append(.init(key: .study))
        }
        if let v = attributes["path_to_residency"], allowed(v) {
            out.append(.init(key: .residency, years: number(v, "years")))
        }
        if let v = attributes["family_inclusion"], allowed(v) {
            out.append(.init(key: .family))
        }
        return out
    }

    /// `marketing.visaChecker.routes.rights.*`.
    var label: String {
        switch key {
        case .work:
            if let hours { return String(localized: "Work \(hours) h/week") }
            return String(localized: "Work allowed")
        case .study:
            return String(localized: "Study allowed")
        case .residency:
            if let years { return String(localized: "Residency after \(years) years") }
            return String(localized: "Path to residency")
        case .family:
            return String(localized: "Family included")
        }
    }
}

/// `CheckerRoutesResponse`: the localized visa types that have a route
/// somewhere (purpose order), and destination ISO2 → its routes for the purpose.
struct CheckerRoutes: Sendable, Hashable {
    struct VisaType: Sendable, Hashable, Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    let purpose: Purpose
    let types: [VisaType]
    let destinations: [String: [CheckerRoute]]

    /// The visa type's localized name, or its code.
    func typeName(_ code: String) -> String {
        types.first { $0.code == code }?.name ?? code
    }
}

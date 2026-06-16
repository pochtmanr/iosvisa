import Foundation

/// The five onboarding goals, mirroring `web/src/lib/onboarding/goals.ts`. Stored
/// as a `text[]` in `profiles.goal`.
enum TravelGoal: String, CaseIterable, Identifiable, Sendable {
    case travel
    case workAbroad = "work_abroad"
    case immigrate
    case study
    case invest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .travel: return "Travel"
        case .workAbroad: return "Work abroad"
        case .immigrate: return "Immigrate"
        case .study: return "Study"
        case .invest: return "Invest"
        }
    }

    var detail: String {
        switch self {
        case .travel: return "Trips, tourism and short stays."
        case .workAbroad: return "Employment, freelance or remote work."
        case .immigrate: return "Settle long-term — family, ancestry, retirement."
        case .study: return "Universities, courses and exchanges."
        case .invest: return "Golden visas and residency by investment."
        }
    }
}

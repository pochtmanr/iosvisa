import Foundation

/// Inputs to the profile-completeness calculation — a flat snapshot so the
/// scoring is a pure, testable function (no I/O). Built by the dashboard from
/// the profile row + vault section counts.
struct CompletenessInput: Sendable, Equatable {
    var personalComplete: Bool
    var contactComplete: Bool
    var passports: Int
    var residencies: Int
    var education: Int
    var employment: Int
    var family: Int
    var travel: Int
    var background: Int
}

/// One section's completion state, for the dashboard checklist hint.
struct CompletenessSection: Identifiable, Sendable, Equatable {
    let key: String
    let label: String
    let complete: Bool
    var id: String { key }
}

/// Result of scoring: the rounded percentage and the per-section breakdown.
struct Completeness: Sendable, Equatable {
    let percent: Int
    let sections: [CompletenessSection]

    var completeCount: Int { sections.filter(\.complete).count }
    var totalCount: Int { sections.count }
}

/// Pure profile-completeness scorer — the iOS port of the web
/// `computeCompleteness` (9 sections, `round(done / 9 * 100)`).
enum ProfileCompleteness {
    static func compute(_ input: CompletenessInput) -> Completeness {
        let sections: [CompletenessSection] = [
            .init(key: "personal", label: "Personal", complete: input.personalComplete),
            .init(key: "contact", label: "Contact", complete: input.contactComplete),
            .init(key: "passports", label: "Passports", complete: input.passports >= 1),
            .init(key: "residencies", label: "Residencies", complete: input.residencies >= 1),
            .init(key: "education", label: "Education", complete: input.education >= 1),
            .init(key: "employment", label: "Employment", complete: input.employment >= 1),
            .init(key: "family", label: "Family", complete: input.family >= 1),
            .init(key: "travel", label: "Travel history", complete: input.travel >= 1),
            .init(key: "background", label: "Background", complete: input.background >= 1),
        ]
        let done = sections.filter(\.complete).count
        let percent = Int((Double(done) / Double(sections.count) * 100).rounded())
        return Completeness(percent: percent, sections: sections)
    }

    /// Whether the personal section is complete (legal name + DOB), matching
    /// web `isPersonalComplete`.
    static func personalComplete(_ profile: Profile?) -> Bool {
        isFilled(profile?.legalFirstName) && isFilled(profile?.legalLastName) && isFilled(profile?.dateOfBirth)
    }

    /// Whether the contact section is complete (phone + some address), matching
    /// web `isContactComplete`.
    static func contactComplete(_ profile: Profile?) -> Bool {
        guard isFilled(profile?.phone) else { return false }
        if let addr = profile?.residentialAddress, !addr.isEmpty { return true }
        return false
    }

    private static func isFilled(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

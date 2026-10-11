import Foundation

/// The five steps of the application workspace spine (mirrors the web
/// `APPLICATION_STEPS`).
enum WorkspaceStep: String, CaseIterable, Identifiable, Sendable {
    case details, documents, review, payment, tracking
    var id: String { rawValue }

    var label: String {
        switch self {
        case .details: return "Details"
        case .documents: return "Documents"
        case .review: return "Review"
        case .payment: return "Payment"
        case .tracking: return "Tracking"
        }
    }
}

/// Per-step completion/blocked state for the step rail.
struct WorkspaceStepState: Identifiable, Sendable, Equatable {
    let step: WorkspaceStep
    let done: Bool
    let blocked: Bool
    var id: String { step.rawValue }
}

/// The readiness verdict for one application: the three M3 gates plus document
/// progress counts and the per-step states. `ready` is the gate that unlocks the
/// payment step (`draft` → `ready`).
struct Readiness: Sendable, Equatable {
    let profileComplete: Bool
    let detailsConfirmed: Bool
    let documentsAcknowledged: Bool
    let requiredDocsDone: Int
    let requiredDocsTotal: Int
    let docsDone: Int
    let docsTotal: Int
    let steps: [WorkspaceStepState]

    /// M3 gate. Real document attachment is M4 — here the Documents step is
    /// satisfied by an explicit acknowledgment (`documents_acknowledged`),
    /// exactly like the web pre-flight gate. M4 will tighten this to require the
    /// required documents to be uploaded/accepted.
    var ready: Bool { profileComplete && detailsConfirmed && documentsAcknowledged }

    func state(_ step: WorkspaceStep) -> WorkspaceStepState {
        steps.first { $0.step == step } ?? WorkspaceStepState(step: step, done: false, blocked: false)
    }
}

/// Pure readiness engine — no I/O, fully unit-tested. Mirrors the web
/// `computeReadiness` / `computeSteps` adapted for the M3 documents-acknowledge
/// gate.
enum ApplicationReadiness {
    /// Statuses at or after payment — their earlier steps are implicitly done.
    static let postPayment: Set<ApplicationStatus> = [
        .paid, .offered, .claimed, .inProgress, .docsRequested,
        .submittedToAuthority, .decisionPending,
        .approved, .refused, .completed, .cancelled, .refunded,
    ]
    /// Terminal outcomes — the tracking step is "done".
    static let terminal: Set<ApplicationStatus> = [
        .approved, .refused, .completed, .cancelled, .refunded,
    ]

    static func evaluate(
        status: ApplicationStatus,
        details: ApplicantDetails,
        category: VisaCategory,
        checklist: [ChecklistItem],
        profile: Profile?,
        passportCount: Int,
        employmentCount: Int = 0,
        educationCount: Int = 0,
        familyCount: Int = 0
    ) -> Readiness {
        let past = postPayment.contains(status)

        // Profile completeness: baseline (personal + contact + a passport),
        // extended by the product's category, mirroring web
        // REQUIRED_SECTIONS_BY_CATEGORY.
        let personalOK = isFilled(profile?.legalFirstName)
            && isFilled(profile?.legalLastName)
            && isFilled(profile?.dateOfBirth)
        let contactOK = isFilled(profile?.phone)
        let passportsOK = passportCount >= 1
        var profileComplete = personalOK && contactOK && passportsOK
        switch category {
        case .work: profileComplete = profileComplete && employmentCount >= 1
        case .study: profileComplete = profileComplete && educationCount >= 1
        case .family: profileComplete = profileComplete && familyCount >= 1
        default: break
        }

        let detailsConfirmed = past || details.detailsConfirmed
        let documentsAcknowledged = past || details.documentsAcknowledged

        let requiredItems = checklist.filter { $0.requirement.required }
        let requiredDocsTotal = requiredItems.count
        let requiredDocsDone = requiredItems.filter { $0.isSatisfied }.count
        let docsTotal = checklist.count
        let docsDone = checklist.filter { $0.isSatisfied }.count

        let ready = profileComplete && detailsConfirmed && documentsAcknowledged

        let steps: [WorkspaceStepState] = [
            WorkspaceStepState(step: .details, done: detailsConfirmed, blocked: false),
            WorkspaceStepState(step: .documents, done: documentsAcknowledged, blocked: false),
            WorkspaceStepState(step: .review, done: past || status == .ready, blocked: false),
            WorkspaceStepState(step: .payment, done: past,
                               blocked: !past && !(status == .ready || ready)),
            WorkspaceStepState(step: .tracking, done: terminal.contains(status), blocked: false),
        ]

        return Readiness(
            profileComplete: profileComplete,
            detailsConfirmed: detailsConfirmed,
            documentsAcknowledged: documentsAcknowledged,
            requiredDocsDone: requiredDocsDone,
            requiredDocsTotal: requiredDocsTotal,
            docsDone: docsDone,
            docsTotal: docsTotal,
            steps: steps
        )
    }

    /// Which step to open first: tracking once paid, otherwise the first step
    /// that is neither done nor blocked, falling back to payment.
    static func defaultStep(status: ApplicationStatus, readiness: Readiness) -> WorkspaceStep {
        if postPayment.contains(status) { return .tracking }
        let next = readiness.steps.first { !$0.done && !$0.blocked }
        return next?.step ?? .payment
    }

    private static func isFilled(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

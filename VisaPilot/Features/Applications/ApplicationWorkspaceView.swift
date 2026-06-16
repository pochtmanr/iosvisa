import SwiftUI
import Observation

/// The step-driven application workspace: a rail of steps (Details → Documents →
/// Review → Payment → Tracking) over the active step's body, gated by a pure
/// readiness model. Payment unlocks once the readiness gate passes; checkout
/// itself lands in M5.
struct ApplicationWorkspaceView: View {
    @State private var model: ApplicationWorkspaceModel
    @State private var step: WorkspaceStep = .details
    @State private var didPickInitialStep = false

    init(application: VisaApplication) {
        _model = State(initialValue: ApplicationWorkspaceModel(application: application))
    }

    var body: some View {
        VStack(spacing: 0) {
            StepRail(steps: model.readiness.steps, selected: step) { tapped in
                step = tapped
            }
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    body(for: step)
                    AdvisoryDisclaimer()
                }
                .padding(Spacing.xl)
            }
        }
        .background(Theme.bg)
        .navigationTitle(model.destinationName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if !didPickInitialStep {
                step = ApplicationReadiness.defaultStep(status: model.application.status, readiness: model.readiness)
                didPickInitialStep = true
            }
        }
    }

    @ViewBuilder
    private func body(for step: WorkspaceStep) -> some View {
        switch step {
        case .details:
            DetailsFormView(model: model) { self.step = .documents }
        case .documents:
            DocumentsChecklistView(model: model) { self.step = .review }
        case .review:
            ReviewStepView(model: model) { self.step = .payment }
        case .payment:
            PaymentStepView(model: model)
        case .tracking:
            TrackingStepView(model: model)
        }
    }
}

// MARK: - Step rail

/// Horizontal rail of the five steps with done / blocked / selected affordances.
struct StepRail: View {
    let steps: [WorkspaceStepState]
    let selected: WorkspaceStep
    let onSelect: (WorkspaceStep) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(steps) { state in
                    Button { if !state.blocked { onSelect(state.step) } } label: {
                        HStack(spacing: Spacing.xs) {
                            icon(for: state)
                            Text(state.step.label)
                                .typography(.sm)
                                .foregroundStyle(state.step == selected ? Theme.ink : Theme.textSoft)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(state.step == selected ? Theme.surface : .clear, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                state.step == selected ? Theme.border : .clear,
                                lineWidth: Hairline.width)
                        )
                        .opacity(state.blocked ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.blocked)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
    }

    @ViewBuilder
    private func icon(for state: WorkspaceStepState) -> some View {
        if state.done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14)).foregroundStyle(StatusHue.green.solid)
        } else if state.blocked {
            Image(systemName: "lock")
                .font(.system(size: 12)).foregroundStyle(Theme.textSoft)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 13)).foregroundStyle(Theme.textSoft)
        }
    }
}

// MARK: - Review step

private struct ReviewStepView: View {
    @Bindable var model: ApplicationWorkspaceModel
    var onContinue: () -> Void

    var body: some View {
        let details = model.application.details
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Review")
            Text("Check everything before payment").typography(.h3).foregroundStyle(Theme.ink)

            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    summary("Applicant", fullName(details))
                    summary("Date of birth", DateOnly.displayString(details.string(.dateOfBirth)) ?? "—")
                    summary("Passport no.", valueOrDash(details.string(.passportNumber)))
                    if let product = model.resolved?.product.name { summary("Visa type", product) }
                    if let fee = model.resolved?.feeDisplay { summary("Fee", fee) }
                }
            }

            stat("Documents", "\(model.readiness.docsDone) of \(model.readiness.docsTotal) ready")
            stat("Profile", model.readiness.profileComplete ? "Complete" : "Needs attention")

            PrimaryButton(title: model.readiness.ready ? "Continue to payment" : "Finish the steps above",
                          enabled: model.readiness.ready, action: onContinue)
        }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: label)
            Text(value).typography(.body).foregroundStyle(Theme.ink)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).typography(.sm).foregroundStyle(Theme.textBody)
            Spacer()
            Text(value).typography(.sm).foregroundStyle(Theme.ink)
        }
    }

    private func fullName(_ d: ApplicantDetails) -> String {
        let parts = [d.string(.legalFirstName), d.string(.legalMiddleName), d.string(.legalLastName)]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func valueOrDash(_ s: String) -> String { s.isEmpty ? "—" : s }
}

// MARK: - Payment step

private struct PaymentStepView: View {
    @Bindable var model: ApplicationWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Payment")
            Text("Fee preview").typography(.h3).foregroundStyle(Theme.ink)

            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Total due").typography(.body).foregroundStyle(Theme.textBody)
                        Spacer()
                        Text(model.resolved?.feeDisplay ?? "—").typography(.title).foregroundStyle(Theme.ink)
                    }
                    if let proc = model.resolved?.processingDisplay {
                        Text("Estimated processing \(proc).")
                            .typography(.xs).foregroundStyle(Theme.textSoft)
                    }
                }
            }

            if ApplicationReadiness.postPayment.contains(model.application.status) {
                StatusBadge(text: "Paid", hue: .green, icon: "checkmark")
            } else if model.application.status == .ready {
                Text("You're ready to pay. Secure checkout arrives in a later update.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
                PrimaryButton(title: "Proceed to payment", enabled: false) {}
            } else if model.readiness.ready {
                Text("All steps are complete. Mark this application ready to unlock payment.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
                PrimaryButton(title: "Mark as ready to pay", loading: model.saving) {
                    Task { await model.markReady() }
                }
            } else {
                Text("Complete the Details and Documents steps to unlock payment.")
                    .typography(.sm).foregroundStyle(StatusHue.yellow.softFg)
            }

            if let error = model.error {
                Text(error).typography(.sm).foregroundStyle(StatusHue.red.softFg)
            }
        }
    }
}

// MARK: - Tracking step

private struct TrackingStepView: View {
    @Bindable var model: ApplicationWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Tracking")
            Text("Status timeline").typography(.h3).foregroundStyle(Theme.ink)
            StatusTimelineView(
                status: model.application.status,
                createdAt: model.application.createdAt,
                events: model.events,
                assisted: model.isAssisted
            )
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class ApplicationWorkspaceModel {
    var application: VisaApplication
    var resolved: ResolvedVisaProduct?
    var checklist: [ChecklistItem] = []
    var profile: Profile?
    var passportCount = 0
    var counts = VaultSectionCounts()
    var events: [ApplicationStatusEvent] = []
    var loading = true
    var saving = false
    var error: String?

    private let repo = ApplicationRepository()
    private let profiles = ProfileRepository()

    init(application: VisaApplication) { self.application = application }

    var category: VisaCategory { resolved?.product.category ?? .other }
    var isAssisted: Bool { resolved?.effectiveApplicationMode == .assisted }

    /// Destination display name for the nav title (best-effort; the title bar
    /// shows the ISO code until the catalog resolves it elsewhere).
    var destinationName: String { application.destinationIso2 }

    var readiness: Readiness {
        ApplicationReadiness.evaluate(
            status: application.status,
            details: application.details,
            category: category,
            checklist: checklist,
            profile: profile,
            passportCount: passportCount,
            employmentCount: counts.employment,
            educationCount: counts.education,
            familyCount: counts.family
        )
    }

    func load() async {
        loading = true
        defer { loading = false }
        async let resolvedP = repo.resolvedProduct(
            productId: application.productID,
            passport: application.passportIso2,
            destination: application.destinationIso2)
        async let checklistP = repo.checklist(productId: application.productID)
        async let profileP = profiles.currentProfile()
        async let passportCountP = profiles.passportCount()
        async let vaultP = profiles.vaultSectionCounts()
        async let eventsP = repo.timeline(applicationId: application.id)

        resolved = (try? await resolvedP) ?? nil
        let reqs = (try? await checklistP) ?? []
        checklist = reqs.map { ChecklistItem(requirement: $0, status: .missing) }
        profile = (try? await profileP) ?? nil
        passportCount = (try? await passportCountP) ?? 0
        counts = (try? await vaultP) ?? VaultSectionCounts()
        events = (try? await eventsP) ?? []
    }

    /// Persist the edited applicant details (caller has already flipped
    /// `details_confirmed`).
    @discardableResult
    func saveDetails(_ details: ApplicantDetails) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            application = try await repo.update(id: application.id, applicantDetails: details)
            error = nil
            return true
        } catch {
            self.error = "Couldn't save your details. Please try again."
            return false
        }
    }

    /// Set the document-acknowledgment flag (the M3 documents gate).
    @discardableResult
    func setDocumentsAcknowledged(_ on: Bool) async -> Bool {
        guard application.details.documentsAcknowledged != on else { return true }
        var details = application.details
        details.setFlag(.documentsAcknowledged, on)
        return await saveDetails(details)
    }

    /// Owner-allowed draft→ready transition; refreshes the timeline after.
    func markReady() async {
        saving = true
        defer { saving = false }
        do {
            application = try await repo.setStatus(id: application.id, to: .ready)
            events = (try? await repo.timeline(applicationId: application.id)) ?? events
            error = nil
        } catch {
            self.error = "Couldn't mark the application ready. Please try again."
        }
    }
}

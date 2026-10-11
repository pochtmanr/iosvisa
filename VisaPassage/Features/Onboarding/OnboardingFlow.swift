import SwiftUI

/// Three-step onboarding wizard (Goal → Identity → Passport), mirroring web S19.
/// Saves to `profiles` + inserts a primary passport on finish, or stamps
/// `onboarding_completed_at` on skip so the user always reaches the app.
struct OnboardingFlow: View {
    @Environment(AuthStore.self) private var auth

    private let steps = ["Goal", "About you", "Passport"]
    @State private var step = 0

    // Step 1 — goals
    @State private var goals: Set<TravelGoal> = []

    // Step 2 — identity
    @State private var firstName = ""
    @State private var middleName = ""
    @State private var lastName = ""
    @State private var dob: Date?
    @State private var placeOfBirth = ""
    @State private var gender = ""
    @State private var maritalStatus = ""

    // Step 3 — primary passport
    @State private var citizenshipISO2 = ""
    @State private var passportNumber = ""
    @State private var passportExpiry: Date?

    @State private var working = false
    @State private var errorMessage: String?

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        switch step {
                        case 0: goalStep
                        case 1: identityStep
                        default: passportStep
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .typography(.xs)
                                .foregroundStyle(StatusHue.red.softFg)
                        }
                    }
                    .padding(Spacing.xl)
                }
                footer
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Eyebrow(text: "Step \(step + 1) of \(steps.count)")
                Spacer()
                Button("Skip for now") { skip() }
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
                    .disabled(working)
            }
            HStack(spacing: Spacing.sm) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.ink : Theme.border)
                        .frame(height: 4)
                }
            }
            Text(steps[step]).typography(.h2).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            if step > 0 {
                SecondaryButton(title: "Back", icon: "chevron.left") {
                    withAnimation { step -= 1 }
                }
            }
            if step < steps.count - 1 {
                PrimaryButton(title: "Continue") {
                    withAnimation { step += 1 }
                }
            } else {
                PrimaryButton(title: "Finish", icon: "checkmark", loading: working) { finish() }
            }
        }
        .padding(Spacing.xl)
        .background(Theme.bg)
    }

    // MARK: Steps

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What brings you here? Pick any that apply — it tailors what we surface.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
            ForEach(TravelGoal.allCases) { goal in
                goalRow(goal)
            }
        }
    }

    private func goalRow(_ goal: TravelGoal) -> some View {
        let selected = goals.contains(goal)
        return Button {
            if selected { goals.remove(goal) } else { goals.insert(goal) }
        } label: {
            Card(padding: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(goal.label).typography(.title).foregroundStyle(Theme.ink)
                        Text(goal.detail).typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(PressShrinkStyle())
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Your legal details as they appear on your passport. You can edit these anytime.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
            TextFieldRow(label: "Legal first name", text: $firstName, autocapitalization: .words)
            TextFieldRow(label: "Middle name (optional)", text: $middleName, autocapitalization: .words)
            TextFieldRow(label: "Legal last name", text: $lastName, autocapitalization: .words)
            DateField(label: "Date of birth", date: $dob,
                      fromYear: 1900,
                      toYear: Calendar.current.component(.year, from: Date()))
            TextFieldRow(label: "Place of birth (optional)", text: $placeOfBirth, autocapitalization: .words)
            OptionMenuRow(label: "Gender on passport", selection: $gender,
                          options: ["Male", "Female", "X", "Unspecified"])
            OptionMenuRow(label: "Marital status", selection: $maritalStatus,
                          options: ["single", "married", "divorced", "widowed", "separated"])
        }
    }

    private var passportStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Add your main passport — it becomes the default for visa checks. You can add more later.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
            CountryPicker(label: "Citizenship", iso2: $citizenshipISO2)
            TextFieldRow(label: "Passport number (optional)", text: $passportNumber,
                         autocapitalization: .characters)
            DateField(label: "Expiry date (optional)", date: $passportExpiry,
                      fromYear: Calendar.current.component(.year, from: Date()) - 1,
                      toYear: Calendar.current.component(.year, from: Date()) + 15)
            AdvisoryDisclaimer()
        }
    }

    // MARK: Data

    private func prefill() {
        guard let p = auth.profile else { return }
        firstName = p.legalFirstName ?? ""
        middleName = p.legalMiddleName ?? ""
        lastName = p.legalLastName ?? ""
        dob = DateOnly.parse(p.dateOfBirth)
        placeOfBirth = p.placeOfBirth ?? ""
        gender = p.genderOnPassport ?? ""
        maritalStatus = p.maritalStatus ?? ""
    }

    private func finish() {
        errorMessage = nil
        working = true
        Task {
            do {
                let patch = OnboardingFinishPatch(
                    goal: goals.isEmpty ? nil : goals.map(\.rawValue),
                    legal_first_name: trimmedOrNil(firstName),
                    legal_middle_name: trimmedOrNil(middleName),
                    legal_last_name: trimmedOrNil(lastName),
                    date_of_birth: DateOnly.string(dob),
                    place_of_birth: trimmedOrNil(placeOfBirth),
                    gender_on_passport: trimmedOrNil(gender),
                    marital_status: trimmedOrNil(maritalStatus),
                    onboarding_completed_at: Date().ISO8601Format()
                )
                let updated = try await profiles.updateProfile(patch)

                if !citizenshipISO2.isEmpty {
                    let payload = PassportInsert(
                        user_id: updated.id,
                        citizenship_iso2: citizenshipISO2,
                        passport_number: trimmedOrNil(passportNumber),
                        expiry_date: DateOnly.string(passportExpiry),
                        is_primary: true
                    )
                    _ = try await vault.insert(.passports, payload, as: Passport.self)
                }
                auth.markOnboardingComplete(updated)
            } catch {
                errorMessage = "We couldn't save that. Please try again."
                working = false
            }
        }
    }

    private func skip() {
        errorMessage = nil
        working = true
        Task {
            do {
                let updated = try await profiles.updateProfile(
                    OnboardingSkipPatch(onboarding_completed_at: Date().ISO8601Format())
                )
                auth.markOnboardingComplete(updated)
            } catch {
                errorMessage = "We couldn't continue. Please try again."
                working = false
            }
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Insert payload for a new passport row (`user_id` = the signed-in user).
struct PassportInsert: Encodable, Sendable {
    let user_id: UUID
    let citizenship_iso2: String?
    let passport_number: String?
    let expiry_date: String?
    let is_primary: Bool
}

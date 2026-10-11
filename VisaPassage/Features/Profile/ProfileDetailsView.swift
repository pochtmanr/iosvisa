import SwiftUI

/// Personal (legal identity) section — edits the single `profiles` row.
struct ProfileDetailsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private let profiles = ProfileRepository()

    @State private var firstName = ""
    @State private var middleName = ""
    @State private var lastName = ""
    @State private var dob: Date?
    @State private var placeOfBirth = ""
    @State private var gender = ""
    @State private var maritalStatus = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                TextFieldRow(label: "Legal first name", text: $firstName, autocapitalization: .words)
                TextFieldRow(label: "Middle name", text: $middleName, autocapitalization: .words)
                TextFieldRow(label: "Legal last name", text: $lastName, autocapitalization: .words)
                DateField(label: "Date of birth", date: $dob,
                          fromYear: 1900, toYear: Calendar.current.component(.year, from: Date()))
                TextFieldRow(label: "Place of birth", text: $placeOfBirth, autocapitalization: .words)
                OptionMenuRow(label: "Gender on passport", selection: $gender,
                              options: ["Male", "Female", "X", "Unspecified"])
                OptionMenuRow(label: "Marital status", selection: $maritalStatus,
                              options: ["single", "married", "divorced", "widowed", "separated"])
                if let error {
                    Text(error).typography(.xs).foregroundStyle(StatusHue.red.softFg)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle("Personal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if saving { ProgressView() } else { Text("Save") }
                }
                .disabled(saving)
            }
        }
        .onAppear(perform: prefill)
    }

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

    private func save() {
        error = nil
        saving = true
        Task {
            do {
                let patch = PersonalPatch(
                    legal_first_name: firstName.trimmedOrNil,
                    legal_middle_name: middleName.trimmedOrNil,
                    legal_last_name: lastName.trimmedOrNil,
                    date_of_birth: DateOnly.string(dob),
                    place_of_birth: placeOfBirth.trimmedOrNil,
                    gender_on_passport: gender.trimmedOrNil,
                    marital_status: maritalStatus.trimmedOrNil
                )
                _ = try await profiles.updateProfile(patch)
                await auth.refreshProfile()
                dismiss()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

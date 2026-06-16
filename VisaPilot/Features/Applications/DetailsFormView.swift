import SwiftUI

/// The Details step: applicant fields, prefilled from `applicant_details` (which
/// itself was seeded from the profile vault at creation). Saving writes the
/// fields back and flips `details_confirmed`, preserving any server-written keys.
struct DetailsFormView: View {
    @Bindable var model: ApplicationWorkspaceModel
    var onSaved: () -> Void

    @State private var legalFirst = ""
    @State private var legalMiddle = ""
    @State private var legalLast = ""
    @State private var dob: Date?
    @State private var placeOfBirth = ""
    @State private var gender = ""
    @State private var marital = ""
    @State private var passportNumber = ""
    @State private var passportExpiry: Date?
    @State private var phone = ""
    @State private var plannedEntry: Date?
    @State private var plannedDuration = ""
    @State private var priorVisits = false
    @State private var priorVisitsNote = ""
    @State private var loaded = false

    private let genderOptions = ["Male", "Female", "X", "Unspecified"]
    private let maritalOptions = ["single", "married", "divorced", "widowed", "separated"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Applicant details")
            Text("Confirm your information").typography(.h3).foregroundStyle(Theme.ink)
            Text("We've prefilled this from your profile. Review and edit anything that's out of date.")
                .typography(.sm).foregroundStyle(Theme.textBody)

            Card {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    TextFieldRow(label: "Legal first name", text: $legalFirst)
                    TextFieldRow(label: "Legal middle name", text: $legalMiddle)
                    TextFieldRow(label: "Legal last name", text: $legalLast)
                    DateField(label: "Date of birth", date: $dob, toYear: Calendar.current.component(.year, from: Date()))
                    TextFieldRow(label: "Place of birth", text: $placeOfBirth)
                    OptionMenuRow(label: "Gender on passport", selection: $gender, options: genderOptions,
                                  displayName: { $0 })
                    OptionMenuRow(label: "Marital status", selection: $marital, options: maritalOptions)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    TextFieldRow(label: "Passport number", text: $passportNumber,
                                 autocapitalization: .characters)
                    DateField(label: "Passport expiry", date: $passportExpiry)
                    TextFieldRow(label: "Phone", text: $phone, keyboard: .phonePad, contentType: .telephoneNumber)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Eyebrow(text: "Trip")
                    DateField(label: "Planned entry date", date: $plannedEntry)
                    TextFieldRow(label: "Planned duration (days)", text: $plannedDuration, keyboard: .numberPad)
                    ToggleRow(label: "I've visited this country before", isOn: $priorVisits)
                    if priorVisits {
                        TextFieldRow(label: "Notes on prior visits", text: $priorVisitsNote)
                    }
                }
            }

            PrimaryButton(title: "Save & confirm", loading: model.saving) {
                Task { if await save() { onSaved() } }
            }
        }
        .onAppear { if !loaded { populate(); loaded = true } }
    }

    private func populate() {
        let d = model.application.details
        legalFirst = d.string(.legalFirstName)
        legalMiddle = d.string(.legalMiddleName)
        legalLast = d.string(.legalLastName)
        dob = DateOnly.parse(d.string(.dateOfBirth))
        placeOfBirth = d.string(.placeOfBirth)
        gender = d.string(.genderOnPassport)
        marital = d.string(.maritalStatus)
        passportNumber = d.string(.passportNumber)
        passportExpiry = DateOnly.parse(d.string(.passportExpiry))
        phone = d.string(.phone)
        plannedEntry = DateOnly.parse(d.string(.plannedEntryDate))
        plannedDuration = d.string(.plannedDurationDays)
        priorVisits = d.string(.priorVisits) == "yes"
        priorVisitsNote = d.string(.priorVisitsNote)
    }

    private func save() async -> Bool {
        // Start from the existing details so unknown server keys are preserved.
        var d = model.application.details
        d.set(.legalFirstName, legalFirst)
        d.set(.legalMiddleName, legalMiddle)
        d.set(.legalLastName, legalLast)
        d.set(.dateOfBirth, DateOnly.string(dob) ?? "")
        d.set(.placeOfBirth, placeOfBirth)
        d.set(.genderOnPassport, gender)
        d.set(.maritalStatus, marital)
        d.set(.passportNumber, passportNumber)
        d.set(.passportExpiry, DateOnly.string(passportExpiry) ?? "")
        d.set(.phone, phone)
        d.set(.plannedEntryDate, DateOnly.string(plannedEntry) ?? "")
        d.set(.plannedDurationDays, plannedDuration)
        d.set(.priorVisits, priorVisits ? "yes" : "no")
        d.set(.priorVisitsNote, priorVisits ? priorVisitsNote : "")
        d.setFlag(.detailsConfirmed, true)
        return await model.saveDetails(d)
    }
}

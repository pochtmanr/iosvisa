import SwiftUI

/// Contact section — phone, residential + mailing addresses, emergency contact.
/// All stored on the single `profiles` row (addresses + emergency contact are
/// jsonb).
struct ProfileContactView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private let profiles = ProfileRepository()

    @State private var phone = ""

    // Residential
    @State private var rLine1 = ""
    @State private var rLine2 = ""
    @State private var rCity = ""
    @State private var rRegion = ""
    @State private var rPostal = ""
    @State private var rCountry = ""

    // Mailing
    @State private var sameAsResidential = false
    @State private var mLine1 = ""
    @State private var mLine2 = ""
    @State private var mCity = ""
    @State private var mRegion = ""
    @State private var mPostal = ""
    @State private var mCountry = ""

    // Emergency contact
    @State private var ecName = ""
    @State private var ecRelationship = ""
    @State private var ecPhone = ""
    @State private var ecEmail = ""

    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("Phone") {
                    TextFieldRow(label: "Phone number", text: $phone, keyboard: .phonePad,
                                 contentType: .telephoneNumber)
                }
                section("Residential address") {
                    addressFields(line1: $rLine1, line2: $rLine2, city: $rCity,
                                  region: $rRegion, postal: $rPostal, country: $rCountry)
                }
                section("Mailing address") {
                    ToggleRow(label: "Same as residential", isOn: $sameAsResidential)
                    if !sameAsResidential {
                        addressFields(line1: $mLine1, line2: $mLine2, city: $mCity,
                                      region: $mRegion, postal: $mPostal, country: $mCountry)
                    }
                }
                section("Emergency contact") {
                    TextFieldRow(label: "Full name", text: $ecName, autocapitalization: .words)
                    TextFieldRow(label: "Relationship", text: $ecRelationship, autocapitalization: .words)
                    TextFieldRow(label: "Phone", text: $ecPhone, keyboard: .phonePad,
                                 contentType: .telephoneNumber)
                    TextFieldRow(label: "Email", text: $ecEmail, keyboard: .emailAddress,
                                 contentType: .emailAddress, autocapitalization: .never)
                }
                if let error {
                    Text(error).typography(.xs).foregroundStyle(StatusHue.red.softFg)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle("Contact")
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

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: title)
            content()
        }
    }

    @ViewBuilder
    private func addressFields(
        line1: Binding<String>, line2: Binding<String>, city: Binding<String>,
        region: Binding<String>, postal: Binding<String>, country: Binding<String>
    ) -> some View {
        TextFieldRow(label: "Address line 1", text: line1, autocapitalization: .words)
        TextFieldRow(label: "Address line 2", text: line2, autocapitalization: .words)
        TextFieldRow(label: "City", text: city, autocapitalization: .words)
        TextFieldRow(label: "Region / state", text: region, autocapitalization: .words)
        TextFieldRow(label: "Postal code", text: postal, autocapitalization: .characters)
        CountryPicker(label: "Country", iso2: country)
    }

    private func prefill() {
        guard let p = auth.profile else { return }
        phone = p.phone ?? ""
        if let r = p.residentialAddress {
            rLine1 = r.line1 ?? ""; rLine2 = r.line2 ?? ""; rCity = r.city ?? ""
            rRegion = r.region ?? ""; rPostal = r.postalCode ?? ""; rCountry = r.countryISO2 ?? ""
        }
        if let m = p.mailingAddress {
            mLine1 = m.line1 ?? ""; mLine2 = m.line2 ?? ""; mCity = m.city ?? ""
            mRegion = m.region ?? ""; mPostal = m.postalCode ?? ""; mCountry = m.countryISO2 ?? ""
        }
        if let ec = p.emergencyContact {
            ecName = ec.fullName ?? ""; ecRelationship = ec.relationship ?? ""
            ecPhone = ec.phone ?? ""; ecEmail = ec.email ?? ""
        }
    }

    private func save() {
        error = nil
        saving = true
        Task {
            do {
                let residential = PostalAddress(
                    line1: rLine1.trimmedOrNil, line2: rLine2.trimmedOrNil,
                    city: rCity.trimmedOrNil, region: rRegion.trimmedOrNil,
                    postalCode: rPostal.trimmedOrNil, countryISO2: rCountry.trimmedOrNil
                )
                let mailingSource = sameAsResidential
                    ? residential
                    : PostalAddress(
                        line1: mLine1.trimmedOrNil, line2: mLine2.trimmedOrNil,
                        city: mCity.trimmedOrNil, region: mRegion.trimmedOrNil,
                        postalCode: mPostal.trimmedOrNil, countryISO2: mCountry.trimmedOrNil
                      )
                let emergency = EmergencyContact(
                    fullName: ecName.trimmedOrNil, relationship: ecRelationship.trimmedOrNil,
                    phone: ecPhone.trimmedOrNil, email: ecEmail.trimmedOrNil
                )
                let patch = ContactPatch(
                    phone: phone.trimmedOrNil,
                    residential_address: residential.isEmpty ? nil : residential,
                    mailing_address: mailingSource.isEmpty ? nil : mailingSource,
                    emergency_contact: emergency.isEmpty ? nil : emergency
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

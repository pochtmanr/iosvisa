import SwiftUI

/// Residencies & permits vault.
struct ResidenciesView: View {
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Residencies",
            emptyText: "No residence permits yet.",
            load: { try await vault.list(.residencies, as: Residency.self) },
            delete: { try await vault.delete(.residencies, id: $0.id) },
            row: { ResidencyRow(residency: $0) },
            editor: { residency, onDone in ResidencyEditView(residency: residency, onDone: onDone) }
        )
    }
}

private struct ResidencyRow: View {
    let residency: Residency
    @Environment(CountryStore.self) private var countries

    var body: some View {
        VaultRow(
            title: countries.name(forISO2: residency.countryISO2) ?? "Residence",
            subtitle: subtitle
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let type = residency.permitType, !type.isEmpty { parts.append(type) }
        if let expiry = DateOnly.displayString(residency.expiryDate) { parts.append("Expires \(expiry)") }
        return parts.joined(separator: " · ")
    }
}

private struct ResidencyWrite: Encodable, Sendable {
    let user_id: UUID
    let country_iso2: String?
    let permit_type: String?
    let permit_number: String?
    let issue_date: String?
    let expiry_date: String?
}

private struct ResidencyEditView: View {
    let residency: Residency?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var country: String
    @State private var permitType: String
    @State private var permitNumber: String
    @State private var issueDate: Date?
    @State private var expiryDate: Date?
    @State private var saving = false
    @State private var error: String?

    init(residency: Residency?, onDone: @escaping () -> Void) {
        self.residency = residency
        self.onDone = onDone
        _country = State(initialValue: residency?.countryISO2 ?? "")
        _permitType = State(initialValue: residency?.permitType ?? "")
        _permitNumber = State(initialValue: residency?.permitNumber ?? "")
        _issueDate = State(initialValue: DateOnly.parse(residency?.issueDate))
        _expiryDate = State(initialValue: DateOnly.parse(residency?.expiryDate))
    }

    var body: some View {
        VaultEditScaffold(
            title: residency == nil ? "Add residency" : "Edit residency",
            saveTitle: "Save",
            saving: saving,
            canSave: !country.isEmpty,
            onCancel: onDone,
            onSave: save
        ) {
            CountryPicker(label: "Country", iso2: $country)
            TextFieldRow(label: "Permit type", text: $permitType, autocapitalization: .words)
            TextFieldRow(label: "Permit number", text: $permitNumber, autocapitalization: .characters)
            DateField(label: "Issue date", date: $issueDate,
                      fromYear: 1980, toYear: Calendar.current.component(.year, from: Date()))
            DateField(label: "Expiry date", date: $expiryDate,
                      fromYear: Calendar.current.component(.year, from: Date()) - 1,
                      toYear: Calendar.current.component(.year, from: Date()) + 20)
            if let error {
                Text(error).typography(.xs).foregroundStyle(StatusHue.red.softFg)
            }
        }
    }

    private func save() {
        error = nil
        saving = true
        Task {
            do {
                let uid = try await profiles.currentUserID()
                let payload = ResidencyWrite(
                    user_id: uid,
                    country_iso2: country.trimmedOrNil,
                    permit_type: permitType.trimmedOrNil,
                    permit_number: permitNumber.trimmedOrNil,
                    issue_date: DateOnly.string(issueDate),
                    expiry_date: DateOnly.string(expiryDate)
                )
                if let id = residency?.id {
                    _ = try await vault.update(.residencies, id: id, payload, as: Residency.self)
                } else {
                    _ = try await vault.insert(.residencies, payload, as: Residency.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

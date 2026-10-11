import SwiftUI

/// Passports vault — list + add/edit/delete with single-primary enforcement.
struct PassportsView: View {
    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Passports",
            emptyText: "No passports yet. Add the one you travel on.",
            load: { try await profiles.passports() },
            delete: { try await vault.delete(.passports, id: $0.id) },
            row: { PassportRow(passport: $0) },
            editor: { passport, onDone in PassportEditView(passport: passport, onDone: onDone) }
        )
    }
}

private struct PassportRow: View {
    let passport: Passport
    @Environment(CountryStore.self) private var countries

    var body: some View {
        VaultRow(
            title: countries.name(forISO2: passport.citizenshipISO2) ?? "Passport",
            subtitle: subtitle,
            badge: (passport.isPrimary == true) ? "Primary" : nil
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let number = passport.passportNumber, !number.isEmpty {
            parts.append(number.maskedTail)
        }
        if let expiry = DateOnly.displayString(passport.expiryDate) {
            parts.append("Expires \(expiry)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Write payload for `passports` (used for both insert and update — `user_id`
/// is set to the signed-in user either way, which RLS allows).
private struct PassportWrite: Encodable, Sendable {
    let user_id: UUID
    let citizenship_iso2: String?
    let passport_number: String?
    let issue_date: String?
    let expiry_date: String?
    let issuing_authority: String?
    let place_of_issue: String?
    let is_primary: Bool
}

private struct PassportEditView: View {
    let passport: Passport?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var citizenship: String
    @State private var number: String
    @State private var issueDate: Date?
    @State private var expiryDate: Date?
    @State private var issuingAuthority: String
    @State private var placeOfIssue: String
    @State private var isPrimary: Bool
    @State private var saving = false
    @State private var error: String?

    init(passport: Passport?, onDone: @escaping () -> Void) {
        self.passport = passport
        self.onDone = onDone
        _citizenship = State(initialValue: passport?.citizenshipISO2 ?? "")
        _number = State(initialValue: passport?.passportNumber ?? "")
        _issueDate = State(initialValue: DateOnly.parse(passport?.issueDate))
        _expiryDate = State(initialValue: DateOnly.parse(passport?.expiryDate))
        _issuingAuthority = State(initialValue: passport?.issuingAuthority ?? "")
        _placeOfIssue = State(initialValue: passport?.placeOfIssue ?? "")
        _isPrimary = State(initialValue: passport?.isPrimary ?? false)
    }

    var body: some View {
        VaultEditScaffold(
            title: passport == nil ? "Add passport" : "Edit passport",
            saveTitle: "Save",
            saving: saving,
            canSave: !citizenship.isEmpty,
            onCancel: onDone,
            onSave: save
        ) {
            CountryPicker(label: "Citizenship", iso2: $citizenship)
            TextFieldRow(label: "Passport number", text: $number, autocapitalization: .characters)
            DateField(label: "Issue date", date: $issueDate,
                      fromYear: 1980,
                      toYear: Calendar.current.component(.year, from: Date()))
            DateField(label: "Expiry date", date: $expiryDate,
                      fromYear: Calendar.current.component(.year, from: Date()) - 1,
                      toYear: Calendar.current.component(.year, from: Date()) + 20)
            TextFieldRow(label: "Issuing authority", text: $issuingAuthority)
            TextFieldRow(label: "Place of issue", text: $placeOfIssue, autocapitalization: .words)
            ToggleRow(label: "Primary passport", isOn: $isPrimary)
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
                if isPrimary {
                    try await vault.demoteOtherPrimaryPassports(userID: uid, except: passport?.id)
                }
                let payload = PassportWrite(
                    user_id: uid,
                    citizenship_iso2: citizenship.trimmedOrNil,
                    passport_number: number.trimmedOrNil,
                    issue_date: DateOnly.string(issueDate),
                    expiry_date: DateOnly.string(expiryDate),
                    issuing_authority: issuingAuthority.trimmedOrNil,
                    place_of_issue: placeOfIssue.trimmedOrNil,
                    is_primary: isPrimary
                )
                if let id = passport?.id {
                    _ = try await vault.update(.passports, id: id, payload, as: Passport.self)
                } else {
                    _ = try await vault.insert(.passports, payload, as: Passport.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

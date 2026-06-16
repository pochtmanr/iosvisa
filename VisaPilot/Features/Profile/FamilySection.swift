import SwiftUI

/// Family members vault.
struct FamilyView: View {
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Family",
            emptyText: "No family members added yet.",
            load: { try await vault.list(.familyMembers, as: FamilyMember.self) },
            delete: { try await vault.delete(.familyMembers, id: $0.id) },
            row: { FamilyRow(member: $0) },
            editor: { member, onDone in FamilyEditView(member: member, onDone: onDone) }
        )
    }
}

private struct FamilyRow: View {
    let member: FamilyMember
    @Environment(CountryStore.self) private var countries

    var body: some View {
        VaultRow(
            title: member.fullName?.isEmpty == false ? member.fullName! : member.relationship.label,
            subtitle: subtitle
        )
    }

    private var subtitle: String {
        var parts: [String] = [member.relationship.label]
        if let dob = DateOnly.displayString(member.dateOfBirth) { parts.append(dob) }
        if let citizenship = countries.name(forISO2: member.citizenshipISO2) { parts.append(citizenship) }
        return parts.joined(separator: " · ")
    }
}

private struct FamilyWrite: Encodable, Sendable {
    let user_id: UUID
    let relationship: String
    let full_name: String?
    let date_of_birth: String?
    let citizenship_iso2: String?
}

private struct FamilyEditView: View {
    let member: FamilyMember?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var relationship: FamilyRelationship
    @State private var fullName: String
    @State private var dob: Date?
    @State private var citizenship: String
    @State private var saving = false
    @State private var error: String?

    init(member: FamilyMember?, onDone: @escaping () -> Void) {
        self.member = member
        self.onDone = onDone
        _relationship = State(initialValue: member?.relationship ?? .spouse)
        _fullName = State(initialValue: member?.fullName ?? "")
        _dob = State(initialValue: DateOnly.parse(member?.dateOfBirth))
        _citizenship = State(initialValue: member?.citizenshipISO2 ?? "")
    }

    var body: some View {
        VaultEditScaffold(
            title: member == nil ? "Add family member" : "Edit family member",
            saveTitle: "Save",
            saving: saving,
            onCancel: onDone,
            onSave: save
        ) {
            FormField(label: "Relationship") {
                Menu {
                    ForEach(FamilyRelationship.allCases) { option in
                        Button(option.label) { relationship = option }
                    }
                } label: {
                    HStack {
                        Text(relationship.label).typography(.body).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSoft)
                    }
                    .inputStyle()
                }
            }
            TextFieldRow(label: "Full name", text: $fullName, autocapitalization: .words)
            DateField(label: "Date of birth", date: $dob,
                      fromYear: 1900, toYear: Calendar.current.component(.year, from: Date()))
            CountryPicker(label: "Citizenship", iso2: $citizenship)
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
                let payload = FamilyWrite(
                    user_id: uid,
                    relationship: relationship.rawValue,
                    full_name: fullName.trimmedOrNil,
                    date_of_birth: DateOnly.string(dob),
                    citizenship_iso2: citizenship.trimmedOrNil
                )
                if let id = member?.id {
                    _ = try await vault.update(.familyMembers, id: id, payload, as: FamilyMember.self)
                } else {
                    _ = try await vault.insert(.familyMembers, payload, as: FamilyMember.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

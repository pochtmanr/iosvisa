import SwiftUI

/// Education history vault.
struct EducationView: View {
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Education",
            emptyText: "No education entries yet.",
            load: { try await vault.list(.educationEntries, as: EducationEntry.self) },
            delete: { try await vault.delete(.educationEntries, id: $0.id) },
            row: { EducationRow(entry: $0) },
            editor: { entry, onDone in EducationEditView(entry: entry, onDone: onDone) }
        )
    }
}

private struct EducationRow: View {
    let entry: EducationEntry

    var body: some View {
        VaultRow(title: title, subtitle: subtitle)
    }

    private var title: String {
        if let institution = entry.institution, !institution.isEmpty { return institution }
        if let level = entry.level, !level.isEmpty { return level }
        return "Education"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let field = entry.fieldOfStudy, !field.isEmpty { parts.append(field) }
        let start = DateOnly.displayString(entry.startDate)
        let end = DateOnly.displayString(entry.endDate)
        if start != nil || end != nil {
            parts.append("\(start ?? "?") – \(end ?? "Present")")
        }
        return parts.joined(separator: " · ")
    }
}

private struct EducationWrite: Encodable, Sendable {
    let user_id: UUID
    let level: String?
    let institution: String?
    let field_of_study: String?
    let start_date: String?
    let end_date: String?
}

private struct EducationEditView: View {
    let entry: EducationEntry?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var level: String
    @State private var institution: String
    @State private var fieldOfStudy: String
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var saving = false
    @State private var error: String?

    init(entry: EducationEntry?, onDone: @escaping () -> Void) {
        self.entry = entry
        self.onDone = onDone
        _level = State(initialValue: entry?.level ?? "")
        _institution = State(initialValue: entry?.institution ?? "")
        _fieldOfStudy = State(initialValue: entry?.fieldOfStudy ?? "")
        _startDate = State(initialValue: DateOnly.parse(entry?.startDate))
        _endDate = State(initialValue: DateOnly.parse(entry?.endDate))
    }

    var body: some View {
        VaultEditScaffold(
            title: entry == nil ? "Add education" : "Edit education",
            saveTitle: "Save",
            saving: saving,
            onCancel: onDone,
            onSave: save
        ) {
            TextFieldRow(label: "Level (e.g. Bachelor's)", text: $level, autocapitalization: .words)
            TextFieldRow(label: "Institution", text: $institution, autocapitalization: .words)
            TextFieldRow(label: "Field of study", text: $fieldOfStudy, autocapitalization: .words)
            DateField(label: "Start date", date: $startDate,
                      fromYear: 1960, toYear: Calendar.current.component(.year, from: Date()))
            DateField(label: "End date", date: $endDate,
                      fromYear: 1960, toYear: Calendar.current.component(.year, from: Date()) + 10)
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
                let payload = EducationWrite(
                    user_id: uid,
                    level: level.trimmedOrNil,
                    institution: institution.trimmedOrNil,
                    field_of_study: fieldOfStudy.trimmedOrNil,
                    start_date: DateOnly.string(startDate),
                    end_date: DateOnly.string(endDate)
                )
                if let id = entry?.id {
                    _ = try await vault.update(.educationEntries, id: id, payload, as: EducationEntry.self)
                } else {
                    _ = try await vault.insert(.educationEntries, payload, as: EducationEntry.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

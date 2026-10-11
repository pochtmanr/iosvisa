import SwiftUI

/// Employment history vault.
struct EmploymentView: View {
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Employment",
            emptyText: "No employment entries yet.",
            load: { try await vault.list(.employmentEntries, as: EmploymentEntry.self) },
            delete: { try await vault.delete(.employmentEntries, id: $0.id) },
            row: { EmploymentRow(entry: $0) },
            editor: { entry, onDone in EmploymentEditView(entry: entry, onDone: onDone) }
        )
    }
}

private let employmentStatusOptions = ["Employed", "Self-employed", "Student", "Unemployed", "Retired"]
private let incomeRangeOptions = [
    "Under 25k", "25k–50k", "50k–100k", "100k–250k", "Over 250k", "Prefer not to say",
]

private struct EmploymentRow: View {
    let entry: EmploymentEntry

    var body: some View {
        VaultRow(title: title, subtitle: subtitle)
    }

    private var title: String {
        if let employer = entry.employer, !employer.isEmpty { return employer }
        if let status = entry.status, !status.isEmpty { return status }
        return "Employment"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let job = entry.jobTitle, !job.isEmpty { parts.append(job) }
        if let start = DateOnly.displayString(entry.startDate) { parts.append("Since \(start)") }
        return parts.joined(separator: " · ")
    }
}

private struct EmploymentWrite: Encodable, Sendable {
    let user_id: UUID
    let status: String?
    let employer: String?
    let job_title: String?
    let employer_address: String?
    let start_date: String?
    let income_range: String?
    let self_employed: Bool
}

private struct EmploymentEditView: View {
    let entry: EmploymentEntry?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var status: String
    @State private var employer: String
    @State private var jobTitle: String
    @State private var employerAddress: String
    @State private var startDate: Date?
    @State private var incomeRange: String
    @State private var selfEmployed: Bool
    @State private var saving = false
    @State private var error: String?

    init(entry: EmploymentEntry?, onDone: @escaping () -> Void) {
        self.entry = entry
        self.onDone = onDone
        _status = State(initialValue: entry?.status ?? "")
        _employer = State(initialValue: entry?.employer ?? "")
        _jobTitle = State(initialValue: entry?.jobTitle ?? "")
        _employerAddress = State(initialValue: entry?.employerAddress ?? "")
        _startDate = State(initialValue: DateOnly.parse(entry?.startDate))
        _incomeRange = State(initialValue: entry?.incomeRange ?? "")
        _selfEmployed = State(initialValue: entry?.selfEmployed ?? false)
    }

    var body: some View {
        VaultEditScaffold(
            title: entry == nil ? "Add employment" : "Edit employment",
            saveTitle: "Save",
            saving: saving,
            onCancel: onDone,
            onSave: save
        ) {
            OptionMenuRow(label: "Status", selection: $status, options: employmentStatusOptions)
            TextFieldRow(label: "Employer", text: $employer, autocapitalization: .words)
            TextFieldRow(label: "Job title", text: $jobTitle, autocapitalization: .words)
            TextFieldRow(label: "Employer address", text: $employerAddress)
            DateField(label: "Start date", date: $startDate,
                      fromYear: 1960, toYear: Calendar.current.component(.year, from: Date()))
            OptionMenuRow(label: "Income range", selection: $incomeRange,
                          options: incomeRangeOptions, displayName: { $0 })
            ToggleRow(label: "Self-employed", isOn: $selfEmployed)
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
                let payload = EmploymentWrite(
                    user_id: uid,
                    status: status.trimmedOrNil,
                    employer: employer.trimmedOrNil,
                    job_title: jobTitle.trimmedOrNil,
                    employer_address: employerAddress.trimmedOrNil,
                    start_date: DateOnly.string(startDate),
                    income_range: incomeRange.trimmedOrNil,
                    self_employed: selfEmployed
                )
                if let id = entry?.id {
                    _ = try await vault.update(.employmentEntries, id: id, payload, as: EmploymentEntry.self)
                } else {
                    _ = try await vault.insert(.employmentEntries, payload, as: EmploymentEntry.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

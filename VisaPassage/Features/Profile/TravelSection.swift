import SwiftUI

/// Travel history vault.
struct TravelHistoryView: View {
    private let vault = VaultRepository()

    var body: some View {
        VaultSectionView(
            title: "Travel history",
            emptyText: "No trips recorded yet.",
            load: { try await vault.list(.travelEntries, as: TravelEntry.self) },
            delete: { try await vault.delete(.travelEntries, id: $0.id) },
            row: { TravelRow(entry: $0) },
            editor: { entry, onDone in TravelEditView(entry: entry, onDone: onDone) }
        )
    }
}

private struct TravelRow: View {
    let entry: TravelEntry
    @Environment(CountryStore.self) private var countries

    var body: some View {
        VaultRow(title: title, subtitle: subtitle, badge: badge)
    }

    private var title: String {
        countries.name(forISO2: entry.countryISO2) ?? "Trip"
    }

    private var subtitle: String {
        let from = DateOnly.displayString(entry.enteredOn)
        let to = DateOnly.displayString(entry.exitedOn)
        var parts: [String] = []
        if from != nil || to != nil { parts.append("\(from ?? "?") – \(to ?? "?")") }
        if let purpose = entry.purpose, !purpose.isEmpty { parts.append(purpose) }
        return parts.joined(separator: " · ")
    }

    private var badge: String? {
        if entry.wasRefused == true { return "Refused" }
        if entry.overstayed == true { return "Overstay" }
        return nil
    }
}

private struct TravelWrite: Encodable, Sendable {
    let user_id: UUID
    let country_iso2: String?
    let entered_on: String?
    let exited_on: String?
    let purpose: String?
    let had_visa: Bool
    let was_refused: Bool
    let overstayed: Bool
    let notes: String?
}

private struct TravelEditView: View {
    let entry: TravelEntry?
    let onDone: () -> Void

    private let profiles = ProfileRepository()
    private let vault = VaultRepository()

    @State private var country: String
    @State private var enteredOn: Date?
    @State private var exitedOn: Date?
    @State private var purpose: String
    @State private var hadVisa: Bool
    @State private var wasRefused: Bool
    @State private var overstayed: Bool
    @State private var notes: String
    @State private var saving = false
    @State private var error: String?

    init(entry: TravelEntry?, onDone: @escaping () -> Void) {
        self.entry = entry
        self.onDone = onDone
        _country = State(initialValue: entry?.countryISO2 ?? "")
        _enteredOn = State(initialValue: DateOnly.parse(entry?.enteredOn))
        _exitedOn = State(initialValue: DateOnly.parse(entry?.exitedOn))
        _purpose = State(initialValue: entry?.purpose ?? "")
        _hadVisa = State(initialValue: entry?.hadVisa ?? false)
        _wasRefused = State(initialValue: entry?.wasRefused ?? false)
        _overstayed = State(initialValue: entry?.overstayed ?? false)
        _notes = State(initialValue: entry?.notes ?? "")
    }

    var body: some View {
        VaultEditScaffold(
            title: entry == nil ? "Add trip" : "Edit trip",
            saveTitle: "Save",
            saving: saving,
            canSave: !country.isEmpty,
            onCancel: onDone,
            onSave: save
        ) {
            CountryPicker(label: "Country", iso2: $country)
            DateField(label: "Entered on", date: $enteredOn,
                      fromYear: 1960, toYear: Calendar.current.component(.year, from: Date()))
            DateField(label: "Exited on", date: $exitedOn,
                      fromYear: 1960, toYear: Calendar.current.component(.year, from: Date()))
            TextFieldRow(label: "Purpose", text: $purpose, autocapitalization: .sentences)
            ToggleRow(label: "Held a visa", isOn: $hadVisa)
            ToggleRow(label: "Entry was refused", isOn: $wasRefused)
            ToggleRow(label: "Overstayed", isOn: $overstayed)
            TextFieldRow(label: "Notes", text: $notes, autocapitalization: .sentences)
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
                let payload = TravelWrite(
                    user_id: uid,
                    country_iso2: country.trimmedOrNil,
                    entered_on: DateOnly.string(enteredOn),
                    exited_on: DateOnly.string(exitedOn),
                    purpose: purpose.trimmedOrNil,
                    had_visa: hadVisa,
                    was_refused: wasRefused,
                    overstayed: overstayed,
                    notes: notes.trimmedOrNil
                )
                if let id = entry?.id {
                    _ = try await vault.update(.travelEntries, id: id, payload, as: TravelEntry.self)
                } else {
                    _ = try await vault.insert(.travelEntries, payload, as: TravelEntry.self)
                }
                onDone()
            } catch {
                self.error = "Couldn't save. Please try again."
                saving = false
            }
        }
    }
}

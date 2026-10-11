import SwiftUI

/// Searchable country selector backed by the shared `CountryStore`. Binds an
/// ISO-2 code (`""` = none) and shows as a form field that opens a sheet.
struct CountryPicker: View {
    let label: String
    @Binding var iso2: String
    var placeholder: String = String(localized: "Select country")

    @Environment(CountryStore.self) private var countries
    @State private var showing = false

    var body: some View {
        FormField(label: label) {
            Button { showing = true } label: {
                HStack(spacing: Spacing.sm) {
                    if let selected = countries.country(iso2) {
                        CountryFlag(iso2: selected.iso2, size: 18)
                    }
                    Text(selectedName ?? placeholder)
                        .typography(.body)
                        .foregroundStyle(selectedName == nil ? Theme.textSoft : Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSoft)
                }
                .inputStyle()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showing) { sheet }
    }

    private var selectedName: String? {
        guard !iso2.isEmpty else { return nil }
        return countries.name(forISO2: iso2)
    }

    private var sheet: some View {
        NavigationStack {
            CountryListPicker(
                countries: countries.countries,
                selected: iso2.isEmpty ? [] : [iso2.uppercased()]
            ) { country in
                iso2 = country.iso2
                showing = false
            }
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showing = false }
                }
                if !iso2.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear selection") {
                            iso2 = ""
                            showing = false
                        }
                    }
                }
            }
        }
    }
}

/// The searchable country list behind every picker: flag and localized name,
/// a checkmark on selected rows, an optional "Suggested" section on top, and an
/// optional tag per row (e.g. "Primary"). Place it inside a `NavigationStack`.
struct CountryListPicker: View {
    let countries: [Country]
    var selected: [String] = []
    var suggested: [String] = []
    /// Rows that can't be picked right now (e.g. the passport list is full).
    var isDisabled: (Country) -> Bool = { _ in false }
    var tag: (Country) -> String? = { _ in nil }
    let onPick: (Country) -> Void

    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty, !suggestedCountries.isEmpty {
                Section {
                    ForEach(suggestedCountries) { row($0) }
                } header: {
                    Eyebrow(text: "Suggested")
                }
            }
            Section {
                ForEach(filtered) { row($0) }
            } header: {
                if query.isEmpty, !suggestedCountries.isEmpty {
                    Eyebrow(text: "All countries")
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search countries"))
    }

    private var suggestedCountries: [Country] {
        suggested.compactMap { iso in
            countries.first { $0.iso2.caseInsensitiveCompare(iso) == .orderedSame }
        }
    }

    private var filtered: [Country] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return countries }
        return countries.filter {
            $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.name.localizedCaseInsensitiveContains(needle)
                || $0.iso2.caseInsensitiveCompare(needle) == .orderedSame
        }
    }

    private func row(_ country: Country) -> some View {
        let isSelected = selected.contains(country.iso2.uppercased())
        let disabled = !isSelected && isDisabled(country)
        return Button { onPick(country) } label: {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: country.iso2, size: 22)
                Text(country.displayName)
                    .typography(.body)
                    .foregroundStyle(disabled ? Theme.textSoft : Theme.ink)
                Spacer()
                if let tag = tag(country) {
                    Text(tag)
                        .typeRole(.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSoft)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

import SwiftUI

/// Searchable country selector backed by the shared `CountryStore`. Binds an
/// ISO-2 code (`""` = none). Used for every `*_iso2` field in the vault and
/// onboarding.
struct CountryPicker: View {
    let label: String
    @Binding var iso2: String
    var placeholder: String = "Select country"

    @Environment(CountryStore.self) private var countries
    @State private var showing = false
    @State private var query = ""

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

    private var filtered: [Country] {
        let all = countries.countries
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.iso2.localizedCaseInsensitiveContains(query)
        }
    }

    private var sheet: some View {
        NavigationStack {
            List {
                if !iso2.isEmpty {
                    Button {
                        iso2 = ""
                        showing = false
                    } label: {
                        Text("Clear selection").foregroundStyle(Theme.textBody)
                    }
                }
                ForEach(filtered) { country in
                    Button {
                        iso2 = country.iso2
                        showing = false
                    } label: {
                        HStack(spacing: Spacing.md) {
                            CountryFlag(iso2: country.iso2, size: 22)
                            Text(country.name)
                                .typography(.body)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if country.iso2.caseInsensitiveCompare(iso2) == .orderedSame {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search countries")
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showing = false }
                }
            }
        }
    }
}

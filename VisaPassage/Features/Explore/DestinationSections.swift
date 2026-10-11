import SwiftUI

/// Every destination for the selected passports, grouped by visa status in the
/// web's precedence order and searchable. Same data and filter as the map.
struct DestinationListView: View {
    let onSelect: (String) -> Void

    @Environment(ExploreSelection.self) private var explore
    @Environment(PassportPreference.self) private var passports
    @Environment(RequirementsStore.self) private var requirements
    @Environment(CountryStore.self) private var catalog

    @State private var query = ""
    @State private var searchPresented = false

    var body: some View {
        let groups = DestinationGrouping.groups(
            countries: catalog.countries,
            best: requirements.best,
            filter: explore.filter,
            query: query,
            excluding: Set(passports.passports)
        )
        List {
            if groups.isEmpty {
                Text(query.isEmpty ? "No destinations match this filter." : "No destinations match your search.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
                    .listRowBackground(Theme.bg)
            }
            ForEach(groups, id: \.status) { group in
                Section {
                    ForEach(group.entries) { entry in
                        Button { onSelect(entry.country.iso2) } label: {
                            DestinationRow(entry: entry)
                        }
                        .listRowBackground(Theme.bg)
                    }
                } header: {
                    HStack(spacing: Spacing.sm) {
                        MapSwatch(fill: group.status.mapFill)
                        Text(group.status.label)
                        Spacer()
                        Text(verbatim: "\(group.entries.count)")
                    }
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .searchable(text: $query, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search destinations"))
        .onAppear(perform: consumeFocusRequest)
        .onChange(of: explore.focusSearch) { consumeFocusRequest() }
    }

    private func consumeFocusRequest() {
        guard explore.focusSearch else { return }
        explore.focusSearch = false
        // Let the list settle into the navigation bar before focusing.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            searchPresented = true
        }
    }
}

/// Flag, name, and the length of stay when the matrix has one.
private struct DestinationRow: View {
    let entry: DestinationGrouping.Entry

    var body: some View {
        HStack(spacing: Spacing.md) {
            CountryFlag(iso2: entry.country.iso2, size: 24)
            Text(entry.country.displayName)
                .typography(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let days = entry.requirement?.daysAllowed, days > 0 {
                Text("\(days) days")
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSoft)
        }
        .contentShape(Rectangle())
    }
}

/// Pure grouping for the list (and its tests).
enum DestinationGrouping {
    struct Entry: Identifiable, Equatable {
        let country: Country
        let requirement: VisaRequirement?
        var id: String { country.iso2 }
        var status: VisaStatus { requirement?.status ?? .unknown }
    }

    struct Group: Equatable {
        let status: VisaStatus
        let entries: [Entry]
    }

    /// Countries grouped by best status in `VisaStatus.precedence` order (no
    /// data last), filtered by chip and search, without the passports' own
    /// countries. Keeps the catalog's order (sorted by display name) inside a group.
    static func groups(
        countries: [Country],
        best: [String: VisaRequirement],
        filter: ExploreFilter,
        query: String,
        excluding: Set<String>
    ) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        var byStatus: [VisaStatus: [Entry]] = [:]
        for country in countries {
            let iso = country.iso2.uppercased()
            guard !excluding.contains(iso) else { continue }
            if !needle.isEmpty,
               !country.displayName.localizedCaseInsensitiveContains(needle),
               !country.name.localizedCaseInsensitiveContains(needle),
               iso.caseInsensitiveCompare(needle) != .orderedSame {
                continue
            }
            let entry = Entry(country: country, requirement: best[iso])
            guard filter.matches(entry.status) else { continue }
            byStatus[entry.status, default: []].append(entry)
        }
        return VisaStatus.precedence.compactMap { status in
            guard let entries = byStatus[status], !entries.isEmpty else { return nil }
            return Group(status: status, entries: entries)
        }
    }
}

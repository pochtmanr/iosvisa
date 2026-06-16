import SwiftUI

/// A gallery of destinations, grouped by region and searchable. Each cell shows
/// the best visa status for the selected passport(s). Tapping opens the detail.
struct DestinationsView: View {
    let onSelect: (String) -> Void

    @Environment(DiscoverySelection.self) private var selection
    @Environment(CountryStore.self) private var catalog

    @State private var statusByDest: [String: VisaStatus] = [:]
    @State private var loading = true
    @State private var query = ""

    private let visa = VisaRepository()
    private let columns = [GridItem(.flexible(), spacing: Spacing.md),
                           GridItem(.flexible(), spacing: Spacing.md)]

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(.top, Spacing.xxxl)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.xl, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedRegions, id: \.region) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: Spacing.md) {
                                ForEach(group.countries) { country in
                                    Button { onSelect(country.iso2) } label: {
                                        DestinationCell(
                                            country: country,
                                            status: statusByDest[country.iso2.uppercased()] ?? .unknown
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Text(group.region)
                                .typeRole(.eyebrow).textCase(.uppercase)
                                .foregroundStyle(Theme.textSoft)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.sm)
                                .background(Theme.bg)
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .background(Theme.bg)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search destinations")
        .task { await loadStatuses() }
        .onChange(of: selection.selectedPassports) { Task { await loadStatuses() } }
    }

    // MARK: - Data

    private struct RegionGroup { let region: String; let countries: [Country] }

    private var groupedRegions: [RegionGroup] {
        let filtered = catalog.countries.filter { country in
            query.isEmpty
            || country.name.localizedCaseInsensitiveContains(query)
            || country.iso2.localizedCaseInsensitiveContains(query)
        }
        let byRegion = Dictionary(grouping: filtered) { $0.region ?? "Other" }
        return byRegion
            .map { RegionGroup(region: $0.key, countries: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.region < $1.region }
    }

    private func loadStatuses() async {
        loading = true
        defer { loading = false }
        if !selection.selectedPassports.isEmpty {
            statusByDest = (try? await visa.bestStatuses(passports: selection.selectedPassports)) ?? [:]
        } else {
            statusByDest = [:]
        }
    }
}

/// A single destination card: flag, name, and best-status chip.
private struct DestinationCell: View {
    let country: Country
    let status: VisaStatus

    var body: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CountryFlag(iso2: country.iso2, size: 32)
                Text(country.name)
                    .typography(.title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if status != .unknown {
                    StatusBadge(text: status.label, hue: status.hue)
                } else {
                    Text("No data").typography(.xs).foregroundStyle(Theme.textSoft)
                }
            }
        }
    }
}

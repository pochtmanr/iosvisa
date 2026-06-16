import SwiftUI

/// The Discover tab: a passport selector plus a Map / Browse toggle over the
/// passport-strength world map and the destinations gallery. Both views share
/// the same `DiscoverySelection` and push into `DestinationDetailView`.
struct DiscoverView: View {
    @Environment(DiscoverySelection.self) private var selection
    @Environment(CountryStore.self) private var catalog

    @State private var mode: Mode = .map
    @State private var path = NavigationPath()
    @State private var showPassportPicker = false

    enum Mode: String, CaseIterable, Identifiable {
        case map = "Map", browse = "Browse"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                passportBar
                modeToggle
                Divider().overlay(Theme.border)
                content
            }
            .background(Theme.bg)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { iso in
                DestinationDetailView(destinationISO2: iso)
            }
            .navigationDestination(for: NewApplicationRequest.self) { request in
                NewApplicationFlow(request: request) { app in path.append(app) }
            }
            .navigationDestination(for: VisaApplication.self) { app in
                ApplicationWorkspaceView(application: app)
            }
            .sheet(isPresented: $showPassportPicker) {
                PassportPickerSheet()
            }
            .task { await selection.seedFromVaultIfEmpty() }
            .onAppear { consumePendingDestination() }
            .onChange(of: selection.pendingDestination) { consumePendingDestination() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var content: some View {
        if selection.selectedPassports.isEmpty {
            emptyState
        } else {
            switch mode {
            case .map:
                VStack(spacing: 0) {
                    WorldMapView(onSelect: push)
                    Divider().overlay(Theme.border)
                    MapLegend()
                }
            case .browse:
                DestinationsView(onSelect: push)
            }
        }
    }

    private var passportBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                Eyebrow(text: "Passports")
                ForEach(selection.selectedPassports, id: \.self) { iso in
                    passportChip(iso)
                }
                Button { showPassportPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: Hairline.width))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
    }

    private func passportChip(_ iso: String) -> some View {
        let country = catalog.country(iso)
        return Button { selection.toggle(iso) } label: {
            HStack(spacing: Spacing.xs) {
                CountryFlag(iso2: country?.iso2 ?? iso, size: 18)
                Text(iso).typography(.sm).foregroundStyle(Theme.ink)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
        }
        .buttonStyle(.plain)
    }

    private var modeToggle: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.md)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "globe")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkSoft)
            Text("Add a passport to begin").typography(.h3)
            Text("Pick the passport you travel on to see where you can go.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
            Button("Choose passport") { showPassportPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func push(_ iso: String) {
        path.append(iso)
    }

    private func consumePendingDestination() {
        guard let dest = selection.pendingDestination else { return }
        selection.pendingDestination = nil
        push(dest)
    }
}

/// Modal multi-select of the user's candidate passports (any `is_passport`
/// country), searchable. Selecting toggles the discovery selection live.
private struct PassportPickerSheet: View {
    @Environment(DiscoverySelection.self) private var selection
    @Environment(CountryStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var options: [Country] {
        let passportCountries = catalog.countries.filter { $0.isPassport == true }
        guard !query.isEmpty else { return passportCountries }
        return passportCountries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.iso2.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(options) { country in
                Button { selection.toggle(country.iso2) } label: {
                    HStack(spacing: Spacing.md) {
                        CountryFlag(iso2: country.iso2, size: 22)
                        Text(country.name).typography(.body).foregroundStyle(Theme.ink)
                        Spacer()
                        if selection.selectedPassports.contains(country.iso2.uppercased()) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.ink)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Passports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

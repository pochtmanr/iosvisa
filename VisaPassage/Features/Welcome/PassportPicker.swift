import SwiftUI

/// Shared rules for picking passports: only `is_passport` countries, up to two,
/// the first one primary. Suggestions put the device's region first, then the
/// web hero picker's popular passports (`POPULAR_ISO2` in `CountrySelector.tsx`).
enum PassportPicking {
    static let popular = ["UA", "US", "GB", "DE", "FR", "IN", "TR", "RU"]

    static func suggestions(region: String? = Locale.current.region?.identifier) -> [String] {
        var out: [String] = []
        for iso in [region?.uppercased()].compactMap({ $0 }) + popular where !out.contains(iso) {
            out.append(iso)
        }
        return Array(out.prefix(6))
    }

    static func candidates(_ countries: [Country]) -> [Country] {
        countries.filter { $0.isPassport == true }
    }

    /// "Primary" / "Second passport" tag for a selected row.
    static func tag(for iso2: String, in passports: [String]) -> String? {
        switch passports.firstIndex(of: iso2.uppercased()) {
        case 0?: return String(localized: "Primary")
        case 1?: return String(localized: "Second")
        default: return nil
        }
    }
}

/// The welcome flow's last step: "Pick your passport". Works without an
/// account and finishes the welcome either way.
struct PassportPickerStep: View {
    let onFinish: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Add up to two. The first one is your primary passport.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.sm)

                if catalog.countries.isEmpty {
                    if catalog.loadFailed {
                        ContentUnavailableView(
                            "Couldn't load countries",
                            systemImage: "wifi.slash",
                            description: Text("Check your connection and try again.")
                        )
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    PassportList()
                }

                controls
            }
            .background(Theme.bg)
            // A visible bar: the search field lives in its drawer.
            .navigationTitle("Pick your passport")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var controls: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: onFinish) {
                HStack(spacing: Spacing.sm) {
                    Text("Continue").typography(.sm)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Theme.inkInverse)
                .background(Theme.ink.opacity(passports.passports.isEmpty ? 0.3 : 1), in: Capsule())
            }
            .buttonStyle(PressShrinkStyle())
            .disabled(passports.passports.isEmpty)

            Button(action: onFinish) {
                Text("Not now")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(PressShrinkStyle())
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(Theme.bg)
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }
}

/// Edit your passports from Home or Explore.
struct PassportsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PassportList()
                .navigationTitle("Your passports")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The searchable passport list with the two-passport rule. Tapping a selected
/// row removes it; when two are chosen, the rest are disabled.
private struct PassportList: View {
    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog

    var body: some View {
        VStack(spacing: 0) {
            CountryListPicker(
                countries: PassportPicking.candidates(catalog.countries),
                selected: passports.passports,
                suggested: PassportPicking.suggestions(),
                isDisabled: { _ in passports.isFull },
                tag: { PassportPicking.tag(for: $0.iso2, in: passports.passports) }
            ) { country in
                passports.toggle(country.iso2)
            }
            if passports.isFull {
                Text("Two passports selected. Remove one to pick another.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.sm)
                    .background(Theme.surface)
            }
        }
    }
}

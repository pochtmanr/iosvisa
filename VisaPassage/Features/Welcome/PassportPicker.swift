import SwiftUI

/// Shared rules for picking passports: only `is_passport` countries, up to four,
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

    /// "Primary" / "Second" / … tag for a selected row.
    static func tag(for iso2: String, in passports: [String]) -> String? {
        switch passports.firstIndex(of: iso2.uppercased()) {
        case 0?: return String(localized: "Primary")
        case 1?: return String(localized: "Second")
        case 2?: return String(localized: "Third")
        case 3?: return String(localized: "Fourth")
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
                Text("Add up to four. The first one is your primary passport.")
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

extension View {
    /// Edit your passports in a centred dialog (Home, Explore, the tracker).
    func passportsEditor(isPresented: Binding<Bool>) -> some View {
        centredDialog(isPresented: isPresented, maxWidth: 440) { close in
            PassportsEditor(onClose: close)
        }
    }
}

/// Your passports in order: the first is primary. Each row can be made
/// primary or removed; "Add a passport" swaps in the searchable list.
private struct PassportsEditor: View {
    let onClose: () -> Void

    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog
    @State private var adding = false

    var body: some View {
        Group {
            if adding || passports.passports.isEmpty {
                picker
            } else {
                list
            }
        }
        .animation(.snappy(duration: 0.25), value: passports.passports)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your passports").typography(.h3).foregroundStyle(Theme.ink)
                Spacer()
                Button("Done", action: onClose)
                    .typography(.sm)
                    .foregroundStyle(Theme.ink)
            }
            Text("Add up to four. The first one is your primary passport.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(passports.passports.enumerated()), id: \.element) { index, iso in
                    if index > 0 { Divider().overlay(Theme.border) }
                    row(iso, primary: index == 0)
                }
            }

            if passports.isFull {
                Text("Four passports selected. Remove one to pick another.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            } else {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text("Add a passport…").typography(.sm)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .overlay(Capsule().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("passports.add")
            }
        }
        .padding(Spacing.xl)
    }

    private func row(_ iso: String, primary: Bool) -> some View {
        let name = catalog.name(forISO2: iso) ?? iso
        return HStack(spacing: Spacing.md) {
            CountryFlag(iso2: iso, size: 28)
            Text(verbatim: name)
                .typography(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            if primary {
                Text("Primary").typography(.xs).foregroundStyle(Theme.textSoft)
            } else {
                Button("Make primary") { passports.makePrimary(iso) }
                    .typography(.xs)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    .buttonStyle(.plain)
            }
            Button { passports.remove(iso) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28, height: 28)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(name)"))
        }
        .padding(.vertical, Spacing.md)
    }

    /// The searchable list of passports you don't have yet. Picking one adds it
    /// and goes back to your list.
    private var picker: some View {
        NavigationStack {
            CountryListPicker(
                countries: PassportPicking.candidates(catalog.countries)
                    .filter { !passports.contains($0.iso2) },
                suggested: PassportPicking.suggestions().filter { !passports.contains($0) }
            ) { country in
                passports.add(country.iso2)
                adding = false
            }
            .navigationTitle("Add a passport…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if passports.passports.isEmpty {
                        Button("Close", action: onClose)
                    } else {
                        Button("Back") { adding = false }
                    }
                }
            }
        }
        .frame(height: 560)
    }
}

/// The searchable passport list with the four-passport rule. Tapping a selected
/// row removes it; when four are chosen, the rest are disabled.
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
                Text("Four passports selected. Remove one to pick another.")
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

import SwiftUI

/// Every destination for the selected passports as inset-grouped tables, one
/// per visa status in the web's precedence order. Each shows its first
/// `DestinationGrouping.rowLimit` rows, then "Show all"; a search or a status
/// filter shows everything. Place it inside a `List`: it is sections only.
struct DestinationSections: View {
    let groups: [DestinationGrouping.Group]
    /// A search or a filter is active: no row limit.
    let unlimited: Bool
    let onSelect: (String) -> Void

    @State private var expanded: Set<VisaStatus> = []

    var body: some View {
        ForEach(groups, id: \.status) { group in
            let open = unlimited || expanded.contains(group.status)
            let shown = DestinationGrouping.visibleCount(total: group.entries.count, expanded: open)
            Section {
                ForEach(group.entries.prefix(shown)) { entry in
                    Button { onSelect(entry.country.iso2) } label: {
                        DestinationRow(entry: entry)
                    }
                    .foregroundStyle(Theme.ink)
                }
                if !unlimited && group.entries.count > DestinationGrouping.rowLimit {
                    ShowAllRow(expanded: open, hidden: group.entries.count - shown) {
                        if open { expanded.remove(group.status) } else { expanded.insert(group.status) }
                    }
                }
            } header: {
                StatusSectionHeader(count: group.entries.count) {
                    StatusKeyIcon(group.status, size: 16)
                } title: {
                    Text(group.status.label)
                }
            }
        }
    }
}

/// A table's header: glyph, title, count.
struct StatusSectionHeader<Icon: View, Title: View>: View {
    let count: Int
    @ViewBuilder var icon: Icon
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: Spacing.sm) {
            icon
            title
            Spacer()
            Text(verbatim: "\(count)")
                .font(.custom("GeistMono-Regular", size: 12))
                .monospacedDigit()
        }
    }
}

/// "Show all +N" / "Show fewer", at the foot of a limited table.
struct ShowAllRow: View {
    let expanded: Bool
    let hidden: Int
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { onToggle() }
        } label: {
            HStack(spacing: Spacing.md) {
                Text(expanded ? "Show fewer" : "Show all")
                    .font(.custom("Geist-Medium", size: 15))
                    .foregroundStyle(Theme.ink)
                if !expanded && hidden > 0 {
                    Text(verbatim: "+\(hidden)")
                        .font(.custom("GeistMono-Regular", size: 12))
                        .foregroundStyle(Theme.textSoft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surface2, in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.ink)
        .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
    }
}

/// The search field as its own card row (no navigation-bar drawer).
struct DestinationSearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSoft)
            TextField("Search destinations", text: $query)
                .focused(focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.custom("Geist-Regular", size: 16))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSoft)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .frame(minHeight: 28)
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
    /// Rows a table shows before "Show all".
    static let rowLimit = 5

    /// How many of a table's `total` rows show.
    static func visibleCount(total: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, rowLimit)
    }

    /// Destinations per status (the map key's counts), without your own
    /// passports' countries.
    static func counts(countries: [Country], best: [String: VisaRequirement], excluding: Set<String>) -> [VisaStatus: Int] {
        var counts: [VisaStatus: Int] = [:]
        for group in groups(countries: countries, best: best, filter: .all, query: "", excluding: excluding) {
            counts[group.status] = group.entries.count
        }
        return counts
    }

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

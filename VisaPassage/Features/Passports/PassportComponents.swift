import SwiftUI

/// A thin stacked bar of a passport's destinations by status, in the map
/// palette (the web leaderboard's `StatusBar`). Drawn in one `Canvas`, so a
/// 237-row list stays cheap to scroll.
struct PassportStatusBar: View {
    let counts: PassportCounts
    var height: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let total = CGFloat(max(counts.total, 1))
            var x: CGFloat = 0
            for status in PassportCounts.statuses {
                let n = CGFloat(counts[status])
                guard n > 0 else { continue }
                let w = size.width * n / total
                context.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(status.mapFill))
                x += w
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Eyebrow label, big tabular number, optional caption (Home card style).
struct PassportStat: View {
    let label: LocalizedStringKey
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .typeRole(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: value)
                .typography(.h2)
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            if let sub {
                Text(verbatim: sub)
                    .typography(.xs)
                    .foregroundStyle(Theme.textBody)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// All · Africa · Americas · Asia · Europe · Oceania. Tapping the active
/// region clears it, as on the web.
struct RegionChips: View {
    let regions: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip(title: String(localized: "All"), selected: selection == nil) { selection = nil }
                ForEach(regions, id: \.self) { region in
                    chip(title: PassportFilters.regionTitle(region), selected: selection == region) {
                        selection = selection == region ? nil : region
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .typography(.sm)
                .fixedSize()
                .foregroundStyle(selected ? Theme.inkInverse : Theme.ink)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(selected ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Theme.border, lineWidth: Hairline.width))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A compact status pill for dense tables: map swatch + short label.
struct StatusCell: View {
    let status: VisaStatus

    var body: some View {
        HStack(spacing: Spacing.xs) {
            MapSwatch(fill: status.mapFill, size: 8)
            Text(verbatim: status.shortLabel)
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
        }
    }
}

extension VisaStatus {
    /// The web passports page's short labels (`passports.status.*`).
    var shortLabel: String {
        switch self {
        case .visaFree: return String(localized: "Visa-free")
        case .visaOnArrival: return String(localized: "On arrival")
        case .evisa: return String(localized: "eVisa")
        case .eta: return String(localized: "eTA")
        case .visaRequired: return String(localized: "Visa required")
        case .noAdmission: return String(localized: "No entry")
        case .unknown: return String(localized: "No data")
        }
    }
}

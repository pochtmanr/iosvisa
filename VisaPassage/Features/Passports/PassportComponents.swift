import SwiftUI

/// A stacked bar of a passport's destinations by status, in the map palette
/// (web `StatusBar`): segments in `PRECEDENCE` order on a `surface2` track,
/// a hairline gap between them, zero counts skipped. Drawn in one `Canvas`, so
/// a 237-row list stays cheap to scroll.
struct PassportStatusBar: View {
    enum Size {
        /// Leaderboard row on a phone (web `!h-1`).
        case sm
        /// Leaderboard row on a wide screen (web `md:!h-1.5`).
        case md
        /// Passport page and compare (web `lg`).
        case lg

        var height: CGFloat {
            switch self {
            case .sm: return 4
            case .md: return 6
            case .lg: return 10
            }
        }
    }

    let counts: PassportCounts
    var size: Size = .sm

    var body: some View {
        Canvas { context, canvas in
            let present = PassportCounts.statuses.filter { counts[$0] > 0 }
            let gap: CGFloat = 1
            let usable = canvas.width - gap * CGFloat(max(present.count - 1, 0))
            let total = CGFloat(max(counts.total, 1))
            var x: CGFloat = 0
            for status in present {
                let w = usable * CGFloat(counts[status]) / total
                context.fill(Path(CGRect(x: x, y: 0, width: w, height: canvas.height)), with: .color(status.mapFill))
                x += w + gap
            }
        }
        .frame(height: size.height)
        .background(Theme.surface2)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// The six statuses with their duotone icons (web `StatusLegendInfo`). Each
/// item opens the status explainer; with `counts`, zero items are dimmed.
struct StatusLegend: View {
    var counts: PassportCounts? = nil
    var spacing: CGFloat = Spacing.md
    let onSelect: (VisaStatus) -> Void

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(PassportCounts.statuses, id: \.self) { status in
                let count = counts?[status]
                Button { onSelect(status) } label: {
                    HStack(spacing: 6) {
                        StatusKeyIcon(status, size: 16)
                        Text(verbatim: status.shortLabel)
                            .typography(.xs)
                            .foregroundStyle(Theme.textBody)
                        if let count {
                            Text(verbatim: "\(count)")
                                .font(Typography.font(.monoSm))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(count == 0 ? 0.45 : 1)
                .accessibilityLabel(Text(verbatim: count.map { "\(status.shortLabel), \($0)" } ?? status.shortLabel))
                .accessibilityHint(Text("What does this mean?"))
            }
        }
    }
}

/// The status explainer card (web `status-info-dialog`): a tinted icon tile,
/// the title, the plain-language body and an ink Close pill.
struct StatusExplainer: View {
    let status: VisaStatus
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            StatusKeyIcon(status, size: 32)
                .frame(width: 56, height: 56)
                .background(status.mapFill.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: status.explainerTitle)
                    .typography(.h3)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: status.explainerBody)
                    .typography(.body)
                    .foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: close) {
                Text("Close")
                    .typography(.sm)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(PressShrinkStyle())
        }
        .padding(Spacing.xl)
    }
}

extension View {
    /// Presents the status explainer as a centred dialog while `status` is set.
    func statusExplainer(_ status: Binding<VisaStatus?>) -> some View {
        centredDialog(item: status) { value, close in
            StatusExplainer(status: value, close: close)
        }
    }
}

/// Cells on a hairline grid (web stat grid: `gap-px` on `bg-border` inside a
/// rounded clip). Uppercase label, mono value, optional sub-line.
struct HairlineStatGrid: View {
    struct Item: Identifiable {
        let label: LocalizedStringKey
        let value: String
        var sub: String? = nil
        var id: String { "\(label)" + value }
    }

    let items: [Item]
    var columns: Int = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Hairline.width), count: columns),
                  spacing: Hairline.width) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.label)
                        .font(.custom("Geist-Medium", size: 10.5))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(verbatim: item.value)
                        .font(.custom("GeistMono-Regular", size: 28, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let sub = item.sub {
                        Text(verbatim: sub)
                            .typography(.xs)
                            .foregroundStyle(Theme.textBody)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Spacing.lg)
                .background(Theme.bg)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Theme.border)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: Hairline.width))
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

/// All · Africa · Americas · Asia · Europe · Oceania (web region pills).
/// Tapping the active region clears it, as on the web.
struct RegionChips: View {
    let regions: [String]
    @Binding var selection: String?
    var horizontalPadding: CGFloat = Spacing.lg

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                PillChip(title: String(localized: "All"), selected: selection == nil) { selection = nil }
                ForEach(regions, id: \.self) { region in
                    PillChip(title: PassportFilters.regionTitle(region), selected: selection == region) {
                        selection = selection == region ? nil : region
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .scrollClipDisabled()
    }
}

/// A filter pill: ink fill when active, hairline outline otherwise.
struct PillChip<Leading: View>: View {
    let title: String
    let selected: Bool
    var count: Int? = nil
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading
                Text(verbatim: title)
                    .typography(.sm)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(Typography.font(.monoSm))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .fixedSize()
            .foregroundStyle(selected ? Theme.inkInverse : Theme.textBody)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? Theme.ink : Theme.bg, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.ink : Theme.border, lineWidth: Hairline.width))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension PillChip where Leading == EmptyView {
    init(title: String, selected: Bool, count: Int? = nil, action: @escaping () -> Void) {
        self.init(title: title, selected: selected, count: count, action: action) { EmptyView() }
    }
}

/// Rank · Most visa-free · A–Z (web sort control: a `surface2` track with the
/// selected segment raised on `bg`).
struct SortSegmented: View {
    @Binding var selection: PassportFilters.Sort
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PassportFilters.Sort.allCases) { sort in
                let selected = selection == sort
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = sort }
                } label: {
                    Text(verbatim: sort.title)
                        .typography(.xs)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Theme.ink : Theme.textBody)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .padding(.horizontal, Spacing.sm)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.bg)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "sort", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface2, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sort by"))
    }
}

/// A compact status: duotone icon + short label (+ days).
struct StatusCell: View {
    let status: VisaStatus
    var days: Int? = nil
    var iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 5) {
            StatusKeyIcon(status, size: iconSize)
            Text(verbatim: status.shortLabel)
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
            if let days {
                Text("\(days) days")
                    .font(Typography.font(.monoSm))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
            }
        }
    }
}

/// Section title in the web's 28px medium heading style, with an optional lede.
struct PassportSectionTitle: View {
    let title: String
    var lede: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: title)
                .typography(.h3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let lede {
                Text(verbatim: lede)
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Caps content at a readable width and centres it (iPad, landscape).
    func readableWidth(_ max: CGFloat = 960) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
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

    /// Web `passports.statusInfo.{status}.title`.
    var explainerTitle: String {
        switch self {
        case .visaOnArrival: return String(localized: "Visa on arrival")
        default: return shortLabel
        }
    }

    /// Web `passports.statusInfo.{status}.body`.
    var explainerBody: String {
        switch self {
        case .visaFree:
            return String(localized: "No visa needed for a short stay. You show a valid passport at the border and enter. Stay limits still apply, and border officers can ask about your trip, funds or onward ticket.")
        case .visaOnArrival:
            return String(localized: "The visa is issued at the border when you land, so there is nothing to apply for in advance. Expect a fee and a short form at the airport, and sometimes proof of accommodation or a return ticket.")
        case .evisa:
            return String(localized: "A visa you apply for online before you travel. Most applications are decided without a consulate visit. Apply early enough for processing and keep the approval with you.")
        case .eta:
            return String(localized: "No visa, but you need an electronic travel authorisation approved before you board. It's an online form, usually quick, and linked to the passport you travel on.")
        case .visaRequired:
            return String(localized: "You need a visa arranged before you travel, usually through an embassy, consulate or visa centre. Plan ahead: it often takes documents, an appointment and processing time.")
        case .noAdmission:
            return String(localized: "Entry is currently not permitted on this passport, as of our last check. Rules can change, so check official sources before you make plans.")
        case .unknown:
            return String(localized: "We don't have a verified status for this destination yet.")
        }
    }
}

import SwiftUI

/// What the map's colours mean, as a table under the map (web `MapKey`): a
/// title row with the proportion bar, then one row per colour with its glyph
/// and count. Travel rows are the status filter: tapping one narrows the map
/// and the tables, tapping it again clears it. Route rows key the depth ramp.
/// Collapsible; the choice is remembered. Place it in a `List` row with zero
/// insets, like `PurposeList`.
struct MapKeyCard<Footer: View>: View {
    enum Mode {
        /// `counts` is nil while the data loads (counts show "—").
        case travel(counts: [VisaStatus: Int]?, active: ExploreFilter, onToggle: (ExploreFilter) -> Void)
        /// Destinations with 1, 2 and 3+ route types, then no route.
        case route(purpose: Purpose, buckets: [Int]?, none: Int?)
    }

    let mode: Mode
    var showHome = true
    /// Under the rows: the route type chips and the age menu.
    @ViewBuilder var footer: Footer

    @AppStorage("explore.mapKeyOpen") private var open = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            if open {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    divider
                    keyRow(row)
                }
            }
            if Footer.self != EmptyView.self {
                divider
                footer
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Map key"))
    }

    // MARK: - Title

    private var titleRow: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("Map key")
                        .font(.custom("Geist-Medium", size: 15))
                        .foregroundStyle(Theme.ink)
                    // Collapsed, an active filter still shows.
                    if !open, case .travel(_, let active, _) = mode, active != .all {
                        Text(active.title)
                            .font(.custom("Geist-Medium", size: 12))
                            .foregroundStyle(Theme.inkInverse)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.ink, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSoft)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                ShareBar(parts: shareParts)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyHighlightStyle())
        .accessibilityValue(Text(open ? "Expanded" : "Collapsed"))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: Hairline.width)
            .padding(.leading, Spacing.lg + 22 + Spacing.md)
    }

    // MARK: - Rows

    private struct Row {
        enum Icon { case glyph(StatusKeyIcon.Glyph), purpose(Purpose, depth: Int), empty }
        let icon: Icon
        enum Count { case hidden, loading, value(Int) }
        let label: String
        let count: Count
        var filter: ExploreFilter? = nil
    }

    private var rows: [Row] {
        switch mode {
        case .travel(let counts, _, _):
            func n(_ statuses: VisaStatus...) -> Row.Count {
                guard let counts else { return .loading }
                return .value(statuses.reduce(0) { $0 + (counts[$1] ?? 0) })
            }
            var list: [Row] = [
                Row(icon: .glyph(.status(.visaFree)), label: VisaStatus.visaFree.label, count: n(.visaFree), filter: .visaFree),
                Row(icon: .glyph(.status(.visaOnArrival)), label: VisaStatus.visaOnArrival.label, count: n(.visaOnArrival), filter: .onArrival),
                Row(icon: .glyph(.status(.evisa)), label: VisaStatus.evisa.label, count: n(.evisa, .eta), filter: .evisa),
                Row(icon: .glyph(.status(.visaRequired)), label: VisaStatus.visaRequired.label, count: n(.visaRequired), filter: .visaRequired),
                Row(icon: .glyph(.status(.noAdmission)), label: VisaStatus.noAdmission.label, count: n(.noAdmission), filter: .noAdmission),
            ]
            if showHome {
                list.append(Row(icon: .glyph(.home), label: String(localized: "Your passport"), count: .hidden))
            }
            list.append(Row(icon: .glyph(.status(.unknown)), label: VisaStatus.unknown.label, count: n(.unknown)))
            return list
        case .route(let purpose, let buckets, let none):
            var list: [Row] = (0..<3).map { i in
                Row(icon: .purpose(purpose, depth: i + 1),
                    label: i == 2 ? String(localized: "\(3)+ route types") : String(localized: "\(i + 1) route types"),
                    count: buckets.map { .value($0[i]) } ?? .loading)
            }
            list.append(Row(icon: .empty, label: String(localized: "No route found"), count: none.map { .value($0) } ?? .loading))
            if showHome {
                list.append(Row(icon: .glyph(.home), label: String(localized: "Your passport"), count: .hidden))
            }
            return list
        }
    }

    @ViewBuilder
    private func keyRow(_ row: Row) -> some View {
        if case .travel(let counts, let active, let onToggle) = mode, let filter = row.filter {
            let count: Int = if case .value(let n) = row.count { n } else { 0 }
            let isActive = active == filter
            Button {
                withAnimation(.snappy(duration: 0.2)) { onToggle(isActive ? .all : filter) }
            } label: {
                rowBody(row, active: isActive, dimmed: active != .all && !isActive)
            }
            .buttonStyle(KeyHighlightStyle())
            // An empty status can't filter to anything; an active one stays
            // tappable so it can be turned off.
            .disabled(counts == nil || (count == 0 && !isActive))
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityHint(Text("Shows only these destinations on the map and in the list"))
        } else {
            let dimmed: Bool = {
                if case .travel(_, let active, _) = mode { return active != .all }
                return false
            }()
            rowBody(row, active: false, dimmed: dimmed)
                .accessibilityElement(children: .combine)
        }
    }

    private func rowBody(_ row: Row, active: Bool, dimmed: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            icon(row.icon).frame(width: 22, height: 22)
            Text(row.label)
                .font(.custom("Geist-Regular", size: 15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch row.count {
            case .hidden:
                EmptyView()
            case .loading:
                Text(verbatim: "—")
                    .font(.custom("GeistMono-Regular", size: 13))
                    .foregroundStyle(Theme.textSoft)
            case .value(let count):
                Text(verbatim: "\(count)")
                    .font(.custom("GeistMono-Regular", size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSoft)
            }
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .opacity(active ? 1 : 0)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: 44)
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(_ icon: Row.Icon) -> some View {
        switch icon {
        case .glyph(let glyph):
            StatusKeyIcon(glyph: glyph, size: 20)
        case .purpose(let purpose, let depth):
            PurposeIcon(purpose: purpose, size: 18)
                .foregroundStyle(RoutePalette.depth(depth, purpose))
        case .empty:
            MapSwatch(fill: RoutePalette.empty, size: 16)
        }
    }

    // MARK: - Proportion bar

    private var shareParts: [ShareBar.Part] {
        switch mode {
        case .travel(let counts, let active, _):
            let order: [(ExploreFilter?, [VisaStatus], Color)] = [
                (.visaFree, [.visaFree], VisaStatus.visaFree.mapFill),
                (.onArrival, [.visaOnArrival], VisaStatus.visaOnArrival.mapFill),
                (.evisa, [.evisa, .eta], VisaStatus.evisa.mapFill),
                (.visaRequired, [.visaRequired], VisaStatus.visaRequired.mapFill),
                (.noAdmission, [.noAdmission], VisaStatus.noAdmission.mapFill),
                (nil, [.unknown], MapPalette.unknown),
            ]
            return order.enumerated().map { i, entry in
                let n = entry.1.reduce(0) { $0 + (counts?[$1] ?? 0) }
                return ShareBar.Part(id: i, color: entry.2, count: n,
                                     dimmed: active != .all && entry.0 != active)
            }
        case .route(let purpose, let buckets, let none):
            var parts = (0..<3).map { i in
                ShareBar.Part(id: i, color: RoutePalette.depth(i + 1, purpose), count: buckets?[i] ?? 0)
            }
            parts.append(ShareBar.Part(id: 3, color: RoutePalette.empty, count: none ?? 0))
            return parts
        }
    }
}

extension MapKeyCard where Footer == EmptyView {
    init(mode: Mode, showHome: Bool = true) {
        self.init(mode: mode, showHome: showHome) { EmptyView() }
    }
}

/// The web `ShareBar`: one segment per colour, widths in proportion.
struct ShareBar: View {
    struct Part: Identifiable {
        let id: Int
        let color: Color
        let count: Int
        var dimmed = false
    }

    let parts: [Part]

    var body: some View {
        let shown = parts.filter { $0.count > 0 }
        let total = shown.reduce(0) { $0 + $1.count }
        GeometryReader { geo in
            let gaps = CGFloat(max(shown.count - 1, 0))
            let width = max(geo.size.width - gaps, 0)
            HStack(spacing: 1) {
                ForEach(shown) { part in
                    Rectangle()
                        .fill(part.color)
                        .opacity(part.dimmed ? 0.3 : 1)
                        .frame(width: total > 0 ? width * CGFloat(part.count) / CGFloat(total) : 0)
                }
            }
        }
        .frame(height: 6)
        .background(Theme.ink.opacity(0.06))
        .clipShape(Capsule())
        .animation(.snappy(duration: 0.4), value: parts.map(\.count))
        .accessibilityHidden(true)
    }
}

/// The system's grey press highlight on the card's ground.
private struct KeyHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray4) : Color(.secondarySystemGroupedBackground))
    }
}

/// A small rounded tile in a map colour, outlined so pale fills read on paper.
struct MapSwatch: View {
    let fill: Color
    var size: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.12), lineWidth: Hairline.width)
            )
            .frame(width: size, height: size)
    }
}

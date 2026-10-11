import SwiftUI

/// "What's the trip for?" on Home, the rows of an inset grouped section: one
/// row per purpose (glyph in its map accent, title, short line, chevron).
/// Three rows show, then "Show all" opens the rest. A pressed row greys, like
/// a system list. Place it in a `List` row with zero insets.
///
/// The welcome's purpose step keeps the card grid (`PurposeCardGrid`).
struct PurposeList: View {
    /// Gets the "Your goal" pill and a place in the first three rows.
    var suggested: Purpose? = nil
    let onChoose: (Purpose) -> Void

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collapsedCount = 3

    /// Travel first, then the account's goal, then the web's order.
    private var ordered: [Purpose] {
        var list: [Purpose] = [.travel]
        if let suggested, suggested != .travel { list.append(suggested) }
        list += Purpose.allCases.filter { !list.contains($0) }
        return list
    }

    var body: some View {
        let all = ordered
        let shown = expanded ? all : Array(all.prefix(Self.collapsedCount))
        let hidden = all.count - Self.collapsedCount
        VStack(spacing: 0) {
            ForEach(shown) { purpose in
                row(purpose)
                divider
            }
            if hidden > 0 { showAllRow(hidden: hidden) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Purpose of your trip"))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: Hairline.width)
            .padding(.leading, Spacing.lg + 36 + Spacing.md)
    }

    private func row(_ purpose: Purpose) -> some View {
        Button { onChoose(purpose) } label: { EmptyView() }
            .buttonStyle(PurposeRowStyle(purpose: purpose, suggested: purpose == suggested))
        .accessibilityLabel(Text(verbatim: "\(purpose.title), \(purpose.short)"))
        .accessibilityIdentifier("purpose.\(purpose.rawValue)")
        .transition(.opacity)
    }

    private func showAllRow(hidden: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { expanded.toggle() }
        } label: {
            HStack(spacing: Spacing.md) {
                Text(expanded ? "Show fewer" : "Show all")
                    .font(.custom("Geist-Medium", size: 15))
                    .foregroundStyle(Theme.ink)
                if !expanded {
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
            .padding(.leading, Spacing.lg + 36 + Spacing.md)
            .padding(.trailing, Spacing.lg)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightStyle())
        .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
        .accessibilityIdentifier("purpose.showAll")
    }
}

/// One purpose row: bare glyph, title, short line, chevron. Grey when pressed.
private struct PurposeRowStyle: ButtonStyle {
    let purpose: Purpose
    let suggested: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        HStack(spacing: Spacing.md) {
            // Bare glyph, full size, in its purpose's map accent.
            PurposeIcon(purpose: purpose, size: 30)
                .foregroundStyle(RoutePalette.accent(purpose))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(purpose.title)
                        .font(.custom("Geist-Medium", size: 16))
                        .tracking(-0.16)
                        .foregroundStyle(Theme.ink)
                    if suggested {
                        Text("Your goal")
                            .font(.custom("Geist-Medium", size: 11))
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    }
                }
                Text(purpose.short)
                    .font(.custom("Geist-Regular", size: 12.5))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSoft)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The system's grey press highlight; never the ink fill.
        .background(pressed ? Color(.systemGray4) : Color(.secondarySystemGroupedBackground))
        .contentShape(Rectangle())
    }
}

/// The "Show all" row: the system's grey press highlight.
private struct RowHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray4) : Color(.secondarySystemGroupedBackground))
    }
}

#Preview {
    List {
        Section("What's the trip for?") {
            PurposeList(suggested: .study) { _ in }
                .listRowInsets(EdgeInsets())
        }
    }
    .listStyle(.insetGrouped)
}

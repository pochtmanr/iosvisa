import SwiftUI

// Building blocks shared by the corridor, visa product, checklist, guide and
// destination screens. They follow the web guide pages: bare line glyphs in one
// fixed hue per meaning (`ICON_TONE` in `web/src/components/travel/corridorIcons.tsx`),
// hairline grids, and status colour only on badges.

/// Info glyphs with their fixed hue: cost green, time orange, stay purple,
/// issuer and documents blue, zone teal. These hues never mean entry status.
enum CatalogIcon {
    case calendar, coin, hourglass, passport, zone, shieldClock, building, doc, check, info, stamp, globe

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .coin: return "dollarsign.circle"
        case .hourglass: return "hourglass"
        case .passport: return "person.text.rectangle"
        case .zone: return "circle.dashed"
        case .shieldClock: return "clock.badge.checkmark"
        case .building: return "building.columns"
        case .doc: return "doc.text"
        case .check: return "checkmark.circle"
        case .info: return "info.circle"
        case .stamp: return "seal"
        case .globe: return "globe"
        }
    }

    var hue: StatusHue {
        switch self {
        case .calendar: return .purple
        case .coin, .check: return .green
        case .hourglass, .shieldClock: return .orange
        case .passport, .building, .doc, .info, .globe: return .blue
        case .zone, .stamp: return .teal
        }
    }
}

struct CatalogGlyph: View {
    let icon: CatalogIcon
    var size: CGFloat = 20
    /// Pass false to draw in the surrounding foreground (e.g. a muted optional row).
    var tinted: Bool = true

    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: size * 0.82, weight: .regular))
            .frame(width: size, height: size)
            .foregroundStyle(tinted ? AnyShapeStyle(icon.hue.solid) : AnyShapeStyle(Theme.inkSoft))
            .accessibilityHidden(true)
    }
}

/// The landing's section opener: an eyebrow, then a medium headline whose
/// second clause sits in muted ink.
struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var muted: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Eyebrow(verbatim: eyebrow)
            (Text(verbatim: title).foregroundColor(Theme.ink)
             + Text(verbatim: muted.map { " " + $0 } ?? "").foregroundColor(Theme.inkSoft))
                .typography(.h3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "Unverified": the legacy matrix label. A dashed neutral pill with an info
/// glyph, never a status colour (`UnverifiedChip` on the web).
struct UnverifiedChip: View {
    var onDark = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle").font(.system(size: 10.5, weight: .medium))
            Text("Unverified").font(.custom("Geist-Medium", size: 11.5))
        }
        .foregroundStyle(onDark ? Color.white.opacity(0.7) : Theme.inkMuted)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .overlay(
            Capsule().strokeBorder(
                onDark ? Color.white.opacity(0.35) : Theme.ink.opacity(0.25),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
            )
        )
        .fixedSize()
    }
}

/// A neutral white chip on the grouped page (corridor tags, rights).
struct TagChip: View {
    let text: String
    var icon: CatalogIcon? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { CatalogGlyph(icon: icon, size: 15) }
            Text(verbatim: text).font(.custom("Geist-Medium", size: 12.5)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.groupedCard, in: Capsule())
        .fixedSize()
    }
}

/// One cell of a hairline fact grid.
struct FactItem: Identifiable {
    let id: String
    let icon: CatalogIcon
    let label: String
    let value: String?
    let hint: String?
}

/// The signature fact grid: two columns divided by exact 1pt lines inside a
/// borderless 24pt card.
struct FactGrid: View {
    let items: [FactItem]

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
        VStack(spacing: Hairline.width) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Hairline.width) {
                    ForEach(rows[index]) { cell($0) }
                    if rows[index].count == 1 { Theme.groupedCard.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func cell(_ item: FactItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                CatalogGlyph(icon: item.icon, size: 18)
                Text(verbatim: item.label).typeRole(.eyebrow).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(verbatim: item.value ?? "—")
                .typography(.title)
                .foregroundStyle(item.value == nil ? Theme.inkSoft : Theme.ink)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let hint = item.hint {
                Text(verbatim: hint).typography(.xs).foregroundStyle(Theme.textBody).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.groupedCard)
        .accessibilityElement(children: .combine)
    }
}

/// A tappable row in a `Card(padding: 0)` list.
struct CatalogRow<Leading: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var showsChevron = true
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Spacing.md) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).typography(.sm).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(verbatim: subtitle).typography(.xs).foregroundStyle(Theme.textBody)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: Spacing.sm)
            if let trailing {
                Text(verbatim: trailing).font(Typography.font(.monoSm)).foregroundStyle(Theme.textBody)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// Hairline divider inset to line up with row text.
struct RowDivider: View {
    var inset: CGFloat = Spacing.lg
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: Hairline.width).padding(.leading, inset)
    }
}

/// The blue "Apply online" pill: the one filled-colour control on guide pages,
/// linking to the official application site (`ApplyChips` on the web).
struct ApplyOnlineButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Text("Apply online").typography(.sm)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.xl)
            .frame(height: 44)
            .background(Palette.blue500, in: Capsule())
        }
        .buttonStyle(PressShrinkStyle())
        .accessibilityHint(Text("Opens the official application site"))
    }
}

/// A full-width loading / failure card used while a catalog screen resolves.
struct CatalogStateCard: View {
    enum Kind { case loading, failed, empty }
    let kind: Kind
    var message: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch kind {
                case .loading:
                    HStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Checking entry requirements").typography(.sm).foregroundStyle(Theme.textBody)
                    }
                case .failed, .empty:
                    Text(verbatim: message ?? String(localized: "Couldn't load this page. Check your connection and try again."))
                        .typography(.sm).foregroundStyle(Theme.textBody)
                    if let retry {
                        Button(action: retry) {
                            Text("Try again").typography(.sm).foregroundStyle(Theme.ink).underline()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - In-app Safari

// `SafariView` (SFSafariViewController) lives in Features/Profile.

struct SafariLink: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// Presents `link` in an in-app Safari sheet.
    func safariSheet(_ link: Binding<SafariLink?>) -> some View {
        sheet(item: link) { SafariView(url: $0.url).ignoresSafeArea() }
    }
}

import SwiftUI

/// Horizontal map key in the web hero map's palette: one swatch per status,
/// then your passport and no data. eTA shares the eVisa colour, as on the web.
struct MapLegend: View {
    private let statuses: [VisaStatus] = [.visaFree, .visaOnArrival, .evisa, .visaRequired, .noAdmission]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(statuses, id: \.self) { status in
                    item(fill: status.mapFill, label: status.label)
                }
                item(fill: MapPalette.home, label: String(localized: "Your passport"))
                item(fill: MapPalette.unknown, label: VisaStatus.unknown.label)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
        .accessibilityElement(children: .combine)
    }

    private func item(fill: Color, label: String) -> some View {
        HStack(spacing: Spacing.xs) {
            MapSwatch(fill: fill)
            Text(label)
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .fixedSize()
        }
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

import SwiftUI

/// Horizontal legend for the world map — one dot + label per visa status.
struct MapLegend: View {
    /// The five real regimes (excludes `.unknown`, shown as neutral on the map).
    private let statuses: [VisaStatus] = [.visaFree, .visaOnArrival, .evisa, .visaRequired, .noAdmission]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(statuses, id: \.self) { status in
                    HStack(spacing: Spacing.xs) {
                        StatusDot(hue: status.hue, size: 9)
                        Text(status.label)
                            .typography(.xs)
                            .foregroundStyle(Theme.textBody)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
    }
}

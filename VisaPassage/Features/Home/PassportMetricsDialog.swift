import SwiftUI

/// The round ⓘ beside "Your passport" on Home: opens what the card's numbers mean.
struct MetricsInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.inkMuted)
                // 44pt hit area around the glyph.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressShrinkStyle())
        .padding(.vertical, -12)
        .padding(.horizontal, -12)
        .accessibilityLabel(Text("About these numbers"))
        .accessibilityIdentifier("home.passportInfo")
    }
}

/// What Rank, Visa-free and Mobility mean, with this passport's values. A
/// plain iOS-style card on Liquid Glass (centred, never a sheet): each metric
/// is its icon, name and value on one line, the explanation under it.
struct PassportMetricsDialog: View {
    let iso2: String
    let name: String
    let rank: PassportRank?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("How we measure passports")
                    .font(.custom("Geist-SemiBold", size: 17, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    CountryFlag(iso2: iso2, size: 16)
                    Text(verbatim: name)
                        .typography(.xs)
                        .foregroundStyle(Theme.textBody)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                metric(
                    icon: "trophy",
                    title: "Rank",
                    value: rank.map { String(localized: "#\($0.rank) of \($0.totalRanked)") },
                    body: "Position among all passports, by mobility score. Passports with the same score share a rank."
                )
                metric(
                    icon: "checkmark.seal",
                    title: "Visa-free",
                    value: rank.map { "\($0.visaFree)" },
                    body: "Destinations you can enter without a visa or any pre-approval."
                )
                metric(
                    icon: "globe",
                    title: "Mobility",
                    value: rank.map { String(localized: "\($0.mobilityScore) of \($0.known)") },
                    body: "Visa-free plus visa on arrival, out of the destinations we have data for."
                )
            }

            Text("Typical eligibility for short stays, not a promise of admission. Official decisions prevail.")
                .typography(.xs)
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onClose) {
                Text("Done")
                    .font(.custom("Geist-Medium", size: 15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Theme.inkInverse)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(PressShrinkStyle())
        }
        .padding(Spacing.xl)
    }

    private func metric(icon: String, title: LocalizedStringKey, value: String?,
                        body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 22)
                Text(title)
                    .font(.custom("Geist-Medium", size: 15))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Spacing.sm)
                Text(verbatim: value ?? "—")
                    .font(.custom("GeistMono-Regular", size: 14))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Text(body)
                .typography(.xs)
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PassportMetricsDialog(
        iso2: "DE", name: "Germany",
        rank: PassportRank(iso2: "DE", rank: 3, totalRanked: 199, mobilityScore: 171, visaFree: 142, known: 197),
        onClose: {}
    )
    .background(Theme.bg)
}

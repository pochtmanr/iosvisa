import SwiftUI

/// Image cards for sharing a route or a passport rank. Drawn at 360×450pt and
/// rendered at 3× (1080×1350, the 4:5 social size), always in light mode so a
/// shared image looks the same whatever the sender's theme.
enum ShareCardMetrics {
    static let size = CGSize(width: 360, height: 450)
    static let scale: CGFloat = 3
}

/// A passport → destination route with its baseline status.
struct RouteShareCard: View {
    let fromISO2: String
    let fromName: String
    let toISO2: String
    let toName: String
    let status: VisaStatus?
    let daysAllowed: Int?
    let url: URL

    var body: some View {
        ShareCardFrame(url: url) {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: fromISO2, size: 56)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                CountryFlag(iso2: toISO2, size: 56)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("\(fromName) passport").typography(.sm).foregroundStyle(Theme.textBody)
                Text(toName).typography(.h1).foregroundStyle(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            if let status {
                HStack(spacing: Spacing.sm) {
                    StatusBadge(text: status.label, hue: status.hue)
                    if let daysAllowed {
                        Text("Up to \(daysAllowed) days").typography(.sm).foregroundStyle(Theme.textBody)
                    }
                }
            }
        }
    }
}

/// A passport's rank by visa-free access.
struct PassportRankShareCard: View {
    let iso2: String
    let name: String
    let rank: PassportRank
    let url: URL

    var body: some View {
        ShareCardFrame(url: url) {
            CountryFlag(iso2: iso2, size: 64)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("\(name) passport").typography(.title).foregroundStyle(Theme.textBody)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(verbatim: "#\(rank.rank)")
                    .font(.custom("Geist-Medium", size: 72))
                    .tracking(-2)
                    .foregroundStyle(Theme.ink)
                Text("of \(rank.totalRanked) passports").typography(.sm).foregroundStyle(Theme.textBody)
            }
            HStack(spacing: Spacing.sm) {
                StatusBadge(text: String(localized: "Visa-free to \(rank.visaFree)"), hue: .green)
            }
        }
    }
}

/// Shared chrome: paper card, hairline rim, brand mark and the page URL.
private struct ShareCardFrame<Content: View>: View {
    let url: URL
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Image("brand-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Divider().overlay(Theme.border)
                Text(verbatim: displayURL)
                    .typeRole(.monoSm)
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xl + Spacing.xs)
        .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height, alignment: .leading)
        .background(Theme.bg)
        .environment(\.colorScheme, .light)
    }

    private var displayURL: String {
        (url.host ?? "") + url.path
    }
}

#Preview {
    VStack(spacing: 20) {
        RouteShareCard(fromISO2: "UA", fromName: "Ukraine", toISO2: "ES", toName: "Spain",
                       status: .visaFree, daysAllowed: 90,
                       url: URL(string: "https://visapassage.com/travel/ukraine/spain")!)
        PassportRankShareCard(iso2: "UA", name: "Ukraine",
                              rank: PassportRank(iso2: "UA", rank: 31, totalRanked: 199,
                                                 mobilityScore: 140, visaFree: 92, known: 199),
                              url: URL(string: "https://visapassage.com/passports/ukraine")!)
    }
    .scaleEffect(0.6)
}

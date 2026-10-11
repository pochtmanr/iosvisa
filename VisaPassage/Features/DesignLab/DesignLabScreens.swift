#if DEBUG
import SwiftUI

// MARK: - Welcome art

struct LabWelcomePage: View {
    @State private var folderOpen = true

    var body: some View {
        LabNote("The welcome flow's illustrations, drawn by the shipping views. The photo card is clipped to a phone-shaped frame.")

        LabSpecimen(title: "WelcomePage · step 1") {
            WelcomePage(
                number: 1,
                photo: "welcome-plane-above-clouds",
                title: labKey("Add every passport you hold."),
                message: labKey("Citizenships and residence permits in one place. No account needed to start."),
                bottomInset: Spacing.xxl
            ) {
                ZStack {
                    LandingStamp(name: "stamp-singapore", width: 72, rotation: 11)
                        .offset(x: 96, y: -72)
                    LandingStamp(name: "stamp-france", width: 64, rotation: -9)
                        .offset(x: -96, y: -40)
                    PassportFolder(width: 200, open: folderOpen)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                }
            }
            .frame(height: 620)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }

        LabSpecimen(title: "PassportFolder", caption: "Tap to toggle the open (fanned) state.") {
            PassportFolder(width: 232, open: folderOpen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(duration: 0.5)) { folderOpen.toggle() } }
        }

        LabSpecimen(title: "PassportCover · leathers") {
            HStack(spacing: Spacing.md) {
                PassportCover(leather: .navy)
                PassportCover(leather: .burgundy)
                PassportCover(leather: .green)
            }
            .frame(height: 140)
        }
    }
}

// MARK: - Share cards

struct LabShareCardsPage: View {
    private static let url = URL(string: "https://visapassage.com")!

    var body: some View {
        LabNote("Drawn at \(labNumber(ShareCardMetrics.size.width))×\(labNumber(ShareCardMetrics.size.height)) pt and rendered at \(labNumber(ShareCardMetrics.scale))×. Always light, whatever the sender's theme, so they ignore the page appearance.")

        LabSpecimen(title: "RouteShareCard") {
            card {
                RouteShareCard(
                    fromISO2: "gb", fromName: "British",
                    toISO2: "jp", toName: "Japan",
                    status: .visaFree, daysAllowed: 90,
                    url: Self.url
                )
            }
        }
    }

    /// Scales the fixed-size card down to the column width.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let size = ShareCardMetrics.size
        let card = content()
        return GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width)
            card
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
        )
    }
}

// MARK: - Whole screens

/// The app's real screens, presented full screen with the app's live stores.
/// They inherit the environment from Settings, so they show real data.
struct LabFullScreensPage: View {
    private enum Screen: String, Identifiable, CaseIterable {
        case home, explore, myVisas, account, welcome
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .explore: "Explore"
            case .myVisas: "My visas"
            case .account: "Account"
            case .welcome: "Welcome flow"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .explore: "safari"
            case .myVisas: "square.stack"
            case .account: "person.crop.circle"
            case .welcome: "hand.wave"
            }
        }
    }

    @State private var presented: Screen?

    var body: some View {
        LabNote("Each opens over the Lab with a close button in the corner. Use these to check a token change on whole screens.")

        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Screen.allCases) { screen in
                    Button { presented = screen } label: {
                        CatalogRow(title: screen.title) {
                            Image(systemName: screen.icon)
                                .frame(width: 20)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    if screen != Screen.allCases.last { RowDivider() }
                }
            }
        }
        .fullScreenCover(item: $presented) { screen in
            ZStack(alignment: .topTrailing) {
                switch screen {
                case .home: HomeView()
                case .explore: ExploreView()
                case .myVisas: MyVisasView()
                case .account: AccountView()
                case .welcome: WelcomeFlow()
                }
                Button { presented = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                }
                .glassCircle()
                .padding(.trailing, Spacing.lg)
                .padding(.top, Spacing.xxxl + Spacing.xxl)
            }
        }
    }
}
#endif

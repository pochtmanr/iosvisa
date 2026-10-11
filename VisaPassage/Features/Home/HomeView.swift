import SwiftUI

/// The Home tab. IOS-01 placeholder for the dashboard: a greeting in the web
/// `/app` voice and two entry points. IOS-02 adds the passport card, quick
/// search and rule changes; IOS-05 adds the active and done tracker states.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    VStack(spacing: Spacing.md) {
                        EntryCard(
                            icon: "safari",
                            title: "Find a visa",
                            subtitle: "See where your passport can take you."
                        ) { tabs.selection = .explore }
                        EntryCard(
                            icon: "square.stack",
                            title: "My visas",
                            subtitle: "Tick documents off as you collect them."
                        ) { tabs.selection = .visas }
                    }
                    AdvisoryDisclaimer()
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Eyebrow(verbatim: "VisaPassage")
            Group {
                if let name = auth.profile?.displayName {
                    Text("Welcome back, \(name).")
                } else if auth.isSignedIn {
                    Text("Welcome back.")
                } else {
                    Text("Where to next?")
                }
            }
            .typography(.display)
            .foregroundStyle(Theme.ink)

            Text("Find a visa, see what it needs, and tick documents off as you collect them.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
        }
    }
}

/// A tappable hairline card with an icon, a title and one line of help.
struct EntryCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).typography(.title).foregroundStyle(Theme.ink)
                        Text(subtitle).typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                }
            }
        }
        .buttonStyle(PressShrinkStyle())
    }
}

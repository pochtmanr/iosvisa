import SwiftUI

/// The My visas tab. The only place that needs an account: guests see a
/// sign-in gate, signed-in users see the (for now empty) tracker list. The
/// list, create, detail and complete flows land in IOS-05.
struct MyVisasView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TabRouter.self) private var tabs
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Eyebrow(text: "Visa tracker")
                        Text("My visas").typography(.display).foregroundStyle(Theme.ink)
                        Text("One checklist per application. Mark documents as you collect them and follow your submission through to a decision.")
                            .typography(.body)
                            .foregroundStyle(Theme.textBody)
                    }
                    if auth.isSignedIn { emptyState } else { signInGate }
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
        }
        .floatingSheet(isPresented: $showSignIn) { AuthSheet() }
    }

    private var signInGate: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "person.crop.circle").font(.system(size: 28)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Sign in to track your visas").typography(.title).foregroundStyle(Theme.ink)
                    Text("Your trackers sync with your VisaPassage account on the web. Everything else in the app works without an account.")
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                }
                PrimaryButton(title: "Sign in") { showSignIn = true }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Nothing tracked yet").typography(.title).foregroundStyle(Theme.ink)
                    Text("Pick a destination and visa, and we'll set up its document checklist for you to work through at your own pace.")
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                }
                PrimaryButton(title: "Start tracking") { tabs.selection = .explore }
            }
        }
    }
}

import SwiftUI

/// Top-level gate. Guest-first: after a brief launch screen while the stored
/// session resolves, first-time guests see the welcome flow once, then everyone
/// lands on the tab shell. Sign-in is offered from the welcome, Settings and the
/// My visas tab, never forced at launch.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DeepLinkRouter.self) private var router
    @AppStorage(WelcomeFlow.completedKey) private var welcomeCompleted = false

    var body: some View {
        Group {
            if auth.phase == .loading {
                LaunchView()
            } else if !welcomeCompleted && !auth.isSignedIn {
                WelcomeFlow()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.phase == .loading)
        .animation(.easeInOut(duration: 0.3), value: welcomeCompleted)
        // Complete a returning magic-link / OAuth deep link from anywhere.
        .onChange(of: router.pending) { _, newValue in
            if case .authCallback(let url)? = newValue {
                Task {
                    await auth.completeAuthCallback(url)
                    router.consume()
                }
            }
        }
    }
}

/// Brand launch screen shown while the session resolves.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                Text(verbatim: "VisaPassage").typography(.h2).foregroundStyle(Theme.ink)
                ProgressView().tint(Theme.inkSoft)
            }
        }
    }
}

import SwiftUI

/// Top-level gate. Switches between launch, sign-in, onboarding, and the main
/// tab shell based on `AuthStore.phase`.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                LaunchView()
            case .signedOut:
                WelcomeView()
            case .onboarding:
                OnboardingFlow()
            case .ready:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.phase)
        // Complete a returning magic-link / OAuth deep link from anywhere in the
        // auth lifecycle (signed out, or refreshing an expired session).
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
                Text("VisaPassage").typography(.h2).foregroundStyle(Theme.ink)
                ProgressView().tint(Theme.inkSoft)
            }
        }
    }
}

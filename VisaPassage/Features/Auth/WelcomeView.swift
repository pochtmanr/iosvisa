import SwiftUI

/// The signed-out welcome screen. A two-state first impression: an intro collage
/// of floating destinations with a gradient headline and a down-arrow, which on
/// tap slides the collage up and reveals the auth sheet. "Continue with Email"
/// opens the full email form; Apple / Google sign in inline. Replaces the old
/// single-screen `SignInView` at the `.signedOut` gate.
struct WelcomeView: View {
    private enum Stage { case intro, auth }

    @State private var stage: Stage = .intro
    @State private var showEmail = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            DestinationCollage()
                .scaleEffect(stage == .auth ? 1.12 : 1.0, anchor: .top)
                .offset(y: stage == .auth ? -140 : 0)
                .opacity(stage == .auth ? 0.45 : 1.0)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: stage)
                .allowsHitTesting(false)

            switch stage {
            case .intro:
                introOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .auth:
                AuthSheet(onEmail: { showEmail = true })
                    .transition(.move(edge: .bottom))
            }
        }
        .sheet(isPresented: $showEmail) {
            EmailAuthView()
        }
    }

    // MARK: Intro

    private var introOverlay: some View {
        VStack(spacing: Spacing.xl) {
            Text("VisaPassage")
                .typography(.title)
                .foregroundStyle(Theme.textSoft)

            VStack(spacing: 0) {
                Text("Travel without")
                    .foregroundStyle(Theme.ink)
                Text("the paperwork")
                    .foregroundStyle(BrandGradient.accent)
            }
            .typography(.display)
            .multilineTextAlignment(.center)

            arrowButton
                .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.xxxl)
    }

    private var arrowButton: some View {
        Button {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                stage = .auth
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(BrandGradient.accentDiagonal))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PressShrinkStyle())
        .accessibilityLabel("Show sign-in options")
    }
}

#Preview {
    WelcomeView()
}

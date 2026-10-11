import SwiftUI

/// The sign-in card, shown with `.floatingSheet` from the welcome flow, the My
/// visas gate and Settings: the brand mark, a one-line value prop, Apple /
/// Google, "Continue with Email" (opens the full email form) as three
/// identical glass capsules, and a Terms
/// footer. Closes itself once a session exists. All auth logic lives in the
/// button components and `AuthStore`.
struct AuthSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismissFloatingSheet) private var dismissSheet
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header

            VStack(spacing: Spacing.md) {
                AppleSignInButton()
                if AppConfig.hasGoogleSignIn {
                    GoogleSignInButton()
                }
                AuthProviderButton(title: "Continue with Email", systemImage: "envelope") {
                    showEmail = true
                }
            }
            .padding(.top, Spacing.xs)

            if let error = auth.errorMessage {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .medium))
                    Text(error).typography(.xs)
                }
                .foregroundStyle(StatusHue.red.softFg)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StatusHue.red.softBg)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

            Text("By continuing, you agree to VisaPassage's Terms of Use.")
                .typography(.xs)
                .foregroundStyle(Theme.textSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xxl)
        .fullScreenCover(isPresented: $showEmail) { EmailAuthView() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                showEmail = false
                dismissSheet()
            }
        }
        .onDisappear { auth.errorMessage = nil }
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            Image("brand-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text("Sign in")
                    .typography(.h2)
                    .foregroundStyle(Theme.ink)
                Text("Track your visas and keep your passports in sync with the website.")
                    .typography(.body)
                    .foregroundStyle(Theme.textBody)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button { dismissSheet() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .glassCircle()
            .buttonStyle(PressShrinkStyle())
            .accessibilityLabel(Text("Close"))
            .offset(x: Spacing.sm, y: -Spacing.sm)
        }
    }
}

#Preview {
    Color.gray.ignoresSafeArea()
        .floatingSheet(isPresented: .constant(true), surface: .glass) { AuthSheet() }
        .environment(AuthStore())
}

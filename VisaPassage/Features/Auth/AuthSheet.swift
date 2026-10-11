import SwiftUI

/// The slide-up authentication sheet for the welcome screen. Mirrors the
/// reference: a grabber, a one-line value prop, a primary "Continue with Email"
/// action that opens the full email form, an Apple / Google row, and a Terms
/// footer. All auth logic lives in the existing button components / `AuthStore`.
struct AuthSheet: View {
    @Environment(AuthStore.self) private var auth

    /// Invoked when the user taps "Continue with Email".
    let onEmail: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Cosmetic drag handle — the sheet reads as a closable bottom sheet,
            // but it is rendered via `.transition`, so the grabber does nothing.
            Capsule()
                .fill(Theme.inkSoft.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)

            Text("Check where your passport can take you, then track the documents for your visa.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.sm)

            if AppConfig.hasGoogleSignIn {
                GoogleSignInButton()
            }

            AppleSignInButton()
                .frame(maxWidth: .infinity)

            SecondaryButton(title: "Continue with Email", icon: "envelope") {
                onEmail()
            }

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

            termsFooter
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.card,
                topTrailingRadius: Radius.card,
                style: .continuous
            )
            .fill(Theme.bg)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: Radius.card,
                    topTrailingRadius: Radius.card,
                    style: .continuous
                )
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var termsFooter: some View {
        Text("By continuing, you agree to VisaPassage's Terms of Use.")
            .typography(.xs)
            .foregroundStyle(Theme.textSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

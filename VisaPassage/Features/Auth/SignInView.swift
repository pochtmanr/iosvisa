import SwiftUI

/// Full-screen sign-in, opened from Settings or the My visas gate. Apple,
/// Google (when configured) and email. Closes itself once a session exists.
struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var showEmail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Eyebrow(text: "VisaPassage")
                        Text("Sign in").typography(.h1).foregroundStyle(Theme.ink)
                        Text("Track your visas and keep your passports in sync with the website.")
                            .typography(.body)
                            .foregroundStyle(Theme.textBody)
                    }

                    VStack(spacing: Spacing.md) {
                        AppleSignInButton().frame(maxWidth: .infinity)
                        if AppConfig.hasGoogleSignIn { GoogleSignInButton() }
                        SecondaryButton(title: "Continue with Email", icon: "envelope") { showEmail = true }
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

                    Text("By continuing, you agree to VisaPassage's Terms of Use.")
                        .typography(.xs)
                        .foregroundStyle(Theme.textSoft)
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.ink)
                }
            }
        }
        .fullScreenCover(isPresented: $showEmail) { EmailAuthView() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        .onDisappear { auth.errorMessage = nil }
    }
}

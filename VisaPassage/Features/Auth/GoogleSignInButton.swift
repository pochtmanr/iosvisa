import SwiftUI
import GoogleSignIn

/// Native Google sign-in via the GoogleSignIn SDK. Presents Google's consent
/// flow, then hands the returned id-token (+ access token) to Supabase. Only
/// shown when `AppConfig.hasGoogleSignIn` is true (a client ID is configured).
struct GoogleSignInButton: View {
    var title: String = String(localized: "Continue with Google")
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Button {
            startSignIn()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image("google-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title).typography(.sm)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Theme.ink)
            .background(Theme.surfaceCard)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
        }
        .buttonStyle(PressShrinkStyle())
    }

    private func startSignIn() {
        guard let presenter = Self.topViewController() else {
            auth.errorMessage = String(localized: "Couldn't present Google sign-in.")
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: AppConfig.googleIOSClientID)
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
                guard let idToken = result.user.idToken?.tokenString else {
                    auth.errorMessage = String(localized: "Google sign-in returned no token.")
                    return
                }
                _ = await auth.signInWithGoogle(
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            } catch {
                // Silent on user cancellation.
                if (error as? GIDSignInError)?.code == .canceled { return }
                auth.errorMessage = String(localized: "Google sign-in failed. Please try again.")
            }
        }
    }

    /// The frontmost view controller to present the Google flow from.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        let keyWindow = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

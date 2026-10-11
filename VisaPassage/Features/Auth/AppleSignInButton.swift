import SwiftUI
import AuthenticationServices

/// Native Sign in with Apple. Generates a random nonce, sends its SHA-256 in the
/// request, and hands the raw nonce + id-token to Supabase. Works once the Apple
/// provider is enabled on the project (the button always compiles + renders).
struct AppleSignInButton: View {
    @Environment(AuthStore.self) private var auth
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Nonce.random()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Nonce.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(Capsule(style: .continuous))
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = rawNonce
            else {
                auth.errorMessage = String(localized: "Apple sign-in returned no token. Please try again.")
                return
            }
            Task { _ = await auth.signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure(let error):
            // Silent on user cancellation.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            auth.errorMessage = String(localized: "Apple sign-in failed. Please try again.")
        }
    }
}

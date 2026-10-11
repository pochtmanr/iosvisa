import SwiftUI
import AuthenticationServices
import UIKit

/// Sign in with Apple, drawn as the shared glass `AuthProviderButton` so it
/// matches Google and Email (the system `SignInWithAppleButton` fixes its own
/// font and logo size). Runs `ASAuthorizationController` directly: a random
/// nonce, its SHA-256 in the request, then the raw nonce + id-token to Supabase.
struct AppleSignInButton: View {
    @Environment(AuthStore.self) private var auth
    @State private var coordinator = AppleSignInCoordinator()

    var body: some View {
        AuthProviderButton(title: "Continue with Apple", systemImage: "apple.logo") {
            coordinator.start { result in handle(result) }
        }
    }

    private func handle(_ result: Result<(ASAuthorization, String), Error>) {
        switch result {
        case .success(let (authorization, nonce)):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
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

/// Owns one Apple ID authorization request at a time and reports the result
/// with the raw nonce it was made with.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var rawNonce: String?
    private var completion: ((Result<(ASAuthorization, String), Error>) -> Void)?
    private var controller: ASAuthorizationController?

    func start(_ completion: @escaping (Result<(ASAuthorization, String), Error>) -> Void) {
        let nonce = Nonce.random()
        rawNonce = nonce
        self.completion = completion

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            if let nonce = rawNonce {
                finish(.success((authorization, nonce)))
            } else {
                finish(.failure(ASAuthorizationError(.failed)))
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .first { $0.activationState == .foregroundActive } as? UIWindowScene
            return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<(ASAuthorization, String), Error>) {
        completion?(result)
        completion = nil
        controller = nil
        rawNonce = nil
    }
}

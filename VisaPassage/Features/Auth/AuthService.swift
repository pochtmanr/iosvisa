import Foundation
import Supabase

/// Thin wrapper over `SupabaseClientProvider.shared.auth` exposing the M1
/// sign-in surfaces. State transitions are driven by `AuthStore`'s
/// `authStateChanges` observer — these methods just kick off the flows.
struct AuthService {
    var client: SupabaseClient = SupabaseClientProvider.shared
    private var auth: AuthClient { client.auth }

    /// Deep-link target for magic links, OAuth, and password reset returns.
    static let callbackURL = URL(string: "visapassage://auth/callback")!

    // MARK: Native social (id-token) sign-in

    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signInWithGoogle(idToken: String, accessToken: String?) async throws {
        _ = try await auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
    }

    // MARK: Email

    /// Sign up with email + password. Returns `true` when a session was created
    /// immediately (email confirmations disabled); `false` means a confirmation
    /// email was sent.
    func signUpEmail(email: String, password: String) async throws -> Bool {
        let response = try await auth.signUp(
            email: email, password: password, redirectTo: Self.callbackURL
        )
        return response.session != nil
    }

    func signInEmail(email: String, password: String) async throws {
        _ = try await auth.signIn(email: email, password: password)
    }

    /// Send a one-time magic link that returns to `visapassage://auth/callback`.
    func sendMagicLink(email: String) async throws {
        try await auth.signInWithOTP(
            email: email, redirectTo: Self.callbackURL, shouldCreateUser: true
        )
    }

    func resetPassword(email: String) async throws {
        try await auth.resetPasswordForEmail(email, redirectTo: Self.callbackURL)
    }

    // MARK: Deep-link completion

    /// Exchange the code / token_hash carried by a returning deep link for a
    /// session (covers magic-link and OAuth returns).
    func completeAuthCallback(url: URL) async throws {
        _ = try await auth.session(from: url)
    }
}

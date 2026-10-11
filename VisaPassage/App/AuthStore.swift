import Foundation
import Observation
import Supabase

/// Owns the app's authentication + profile state. Observes Supabase auth
/// changes and exposes a coarse `phase`. The app is guest-first: every catalog
/// screen works signed out, and only My visas asks for an account.
@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case loading    // the stored session is still being resolved at launch
        case guest      // no session; catalog screens still work
        case signedIn
    }

    /// Result of an email sign-up attempt, so the UI can branch.
    enum SignUpOutcome: Equatable {
        case signedIn          // session created immediately
        case confirmationSent  // confirmation email sent
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var profile: Profile?
    private(set) var userEmail: String?

    var isSignedIn: Bool { phase == .signedIn }

    /// Surfaced under the sign-in form when a flow fails.
    var errorMessage: String?

    private let client = SupabaseClientProvider.shared
    private let profiles = ProfileRepository()
    private let service = AuthService()
    private var watchTask: Task<Void, Never>?

    /// Begin observing auth state. Call once at app launch.
    func start() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                await self.handle(event: change.event, session: change.session)
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
            if let session, !session.isExpired {
                await loadProfile(email: session.user.email)
            } else {
                phase = .guest
            }
        case .signedOut:
            profile = nil
            userEmail = nil
            phase = .guest
        default:
            break
        }
    }

    /// Mark the user signed in and load (or create) their profile. A profile
    /// failure doesn't sign them out: the session is still valid.
    private func loadProfile(email: String?) async {
        userEmail = email
        phase = .signedIn
        profile = try? await profiles.ensureProfile()
    }

    func signOut() async {
        try? await client.auth.signOut()
        profile = nil
        userEmail = nil
        phase = .guest
    }

    // MARK: Sign-in actions (errors surfaced via `errorMessage`)

    func signInWithEmail(email: String, password: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInEmail(email: email, password: password)
            return true
        } catch {
            errorMessage = String(localized: "Invalid email or password.")
            return false
        }
    }

    func signUpWithEmail(email: String, password: String) async -> SignUpOutcome {
        errorMessage = nil
        do {
            let hasSession = try await service.signUpEmail(email: email, password: password)
            return hasSession ? .signedIn : .confirmationSent
        } catch {
            errorMessage = String(localized: "We couldn't create the account. Please try again.")
            return .failed
        }
    }

    func sendMagicLink(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.sendMagicLink(email: email)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't send the link. Check the address and try again.")
            return false
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.resetPassword(email: email)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't send the reset link. Please try again.")
            return false
        }
    }

    func signInWithApple(idToken: String, nonce: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInWithApple(idToken: idToken, nonce: nonce)
            return true
        } catch {
            errorMessage = String(localized: "Apple sign-in failed. Please try again.")
            return false
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String?) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            return true
        } catch {
            errorMessage = String(localized: "Google sign-in failed. Please try again.")
            return false
        }
    }

    /// Complete a returning magic-link / OAuth deep link.
    func completeAuthCallback(_ url: URL) async {
        errorMessage = nil
        do {
            try await service.completeAuthCallback(url: url)
        } catch {
            errorMessage = String(localized: "That sign-in link has expired. Please request a new one.")
        }
    }
}

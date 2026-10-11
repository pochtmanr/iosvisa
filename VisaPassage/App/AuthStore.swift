import Foundation
import Observation
import Supabase

/// Owns the app's authentication + profile state. Observes Supabase auth
/// changes, loads the profile, and exposes a coarse `phase` the root view
/// switches on. M1 adds the real sign-in actions (Apple/Google/email/magic
/// link) and an `errorMessage` surface; the session lifecycle wiring is from M0.
@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case loading
        case signedOut
        case onboarding   // signed in, onboarding not finished and no passports yet
        case ready        // signed in, onboarding complete
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
            if session != nil {
                await loadProfile()
            } else {
                phase = .signedOut
            }
        case .signedOut:
            profile = nil
            userEmail = nil
            phase = .signedOut
        default:
            break
        }
    }

    /// Load (or create) the profile and decide onboarding vs ready. Mirrors the
    /// web gate: a user is "onboarded" once they've finished the wizard **or**
    /// already hold at least one passport (so existing users never re-enter it).
    func loadProfile() async {
        do {
            userEmail = try await client.auth.session.user.email
            let loaded = try await profiles.ensureProfile()
            profile = loaded
            if loaded.onboardingCompletedAt != nil {
                phase = .ready
            } else {
                let count = (try? await profiles.passportCount()) ?? 0
                let onboarded = OnboardingGate.isOnboarded(
                    onboardingCompletedAt: loaded.onboardingCompletedAt,
                    passportCount: count
                )
                phase = onboarded ? .ready : .onboarding
            }
        } catch {
            // A failure here usually means the token is stale — fall back to
            // signed-out rather than trapping the user on a blank screen.
            phase = .signedOut
        }
    }

    /// Refresh the cached profile after a vault edit (keeps the dashboard
    /// greeting and onboarding gate current).
    func refreshProfile() async {
        if let updated = try? await profiles.currentProfile() {
            profile = updated
        }
    }

    func markOnboardingComplete(_ updated: Profile) {
        profile = updated
        phase = .ready
    }

    func signOut() async {
        try? await client.auth.signOut()
        phase = .signedOut
    }

    // MARK: Sign-in actions (errors surfaced via `errorMessage`)

    func signInWithEmail(email: String, password: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInEmail(email: email, password: password)
            return true
        } catch {
            errorMessage = "Invalid email or password."
            return false
        }
    }

    func signUpWithEmail(email: String, password: String) async -> SignUpOutcome {
        errorMessage = nil
        do {
            let hasSession = try await service.signUpEmail(email: email, password: password)
            return hasSession ? .signedIn : .confirmationSent
        } catch {
            errorMessage = "We couldn't create the account. Please try again."
            return .failed
        }
    }

    func sendMagicLink(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.sendMagicLink(email: email)
            return true
        } catch {
            errorMessage = "We couldn't send the link. Check the address and try again."
            return false
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.resetPassword(email: email)
            return true
        } catch {
            errorMessage = "We couldn't send the reset link. Please try again."
            return false
        }
    }

    func signInWithApple(idToken: String, nonce: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInWithApple(idToken: idToken, nonce: nonce)
            return true
        } catch {
            errorMessage = "Apple sign-in failed. Please try again."
            return false
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String?) async -> Bool {
        errorMessage = nil
        do {
            try await service.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            return true
        } catch {
            errorMessage = "Google sign-in failed. Please try again."
            return false
        }
    }

    /// Complete a returning magic-link / OAuth deep link.
    func completeAuthCallback(_ url: URL) async {
        errorMessage = nil
        do {
            try await service.completeAuthCallback(url: url)
        } catch {
            errorMessage = "That sign-in link has expired. Please request a new one."
        }
    }
}

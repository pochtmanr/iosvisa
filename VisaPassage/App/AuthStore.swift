import Foundation
import Observation
import Supabase
import UIKit

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
    /// From the auth user: the OAuth photo and name (Google `picture`/`name`,
    /// Apple `full_name`), and the linked sign-in methods.
    private(set) var oauthAvatarURL: URL?
    private(set) var oauthName: String?
    private(set) var providers: [String] = []
    /// A round avatar (photo or initials) for the tab bar, rebuilt when the
    /// account's photo or name changes.
    private(set) var tabAvatar: UIImage?
    /// True from sign-in until the profile and its photo are ready, so the
    /// Account header shows one placeholder instead of redrawing piecemeal.
    private(set) var isLoadingProfile = false
    /// The user whose profile is loaded; token refreshes for the same user
    /// don't refetch it.
    private var loadedUserID: UUID?

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
                await loadProfile(user: session.user)
            } else {
                phase = .guest
            }
        case .signedOut:
            clearAccount()
        default:
            break
        }
    }

    /// Mark the user signed in and load (or create) their profile. A profile
    /// failure doesn't sign them out: the session is still valid.
    private func loadProfile(user: User) async {
        if loadedUserID == user.id, profile != nil {
            userEmail = user.email
            phase = .signedIn
            return
        }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        userEmail = user.email
        let meta = user.userMetadata
        oauthAvatarURL = (meta["avatar_url"]?.stringValue ?? meta["picture"]?.stringValue)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        oauthName = [meta["full_name"]?.stringValue, meta["name"]?.stringValue]
            .compactMap { $0 }.first { !$0.isEmpty }
        providers = Self.providers(of: user)
        phase = .signedIn
        profile = try? await profiles.ensureProfile()
        loadedUserID = profile == nil ? nil : user.id
        // Fetch the photo before the header leaves its placeholder, so it
        // appears once, already decoded.
        await refreshTabAvatar()
    }

    func signOut() async {
        try? await client.auth.signOut()
        clearAccount()
    }

    private func clearAccount() {
        profile = nil
        userEmail = nil
        oauthAvatarURL = nil
        oauthName = nil
        providers = []
        tabAvatar = nil
        loadedUserID = nil
        isLoadingProfile = false
        phase = .guest
    }

    // MARK: Account identity

    /// The profile name, then the OAuth name, then the email.
    var displayName: String {
        profile?.displayName ?? oauthName ?? userEmail ?? ""
    }

    /// Up to two initials for the avatar placeholder.
    var initials: String {
        let source = profile?.displayName ?? oauthName ?? userEmail?.split(separator: "@").first.map(String.init) ?? ""
        let words = source.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.joined()
    }

    /// The uploaded photo (public `branding` bucket, as the web's
    /// `publicBrandingUrl`), else the OAuth photo.
    var avatarURL: URL? {
        if let path = profile?.avatarPath, !path.isEmpty {
            return AppConfig.supabaseURL.appending(path: "storage/v1/object/public/branding/\(path)")
        }
        return oauthAvatarURL
    }

    /// Sign-in methods in a stable order (email, apple, google, then others).
    private static func providers(of user: User) -> [String] {
        var names = Set((user.identities ?? []).map { $0.provider.lowercased() })
        if names.isEmpty, let p = user.appMetadata["provider"]?.stringValue { names.insert(p) }
        let order = ["email", "apple", "google"]
        return names.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    // MARK: Profile edits (optimistic; rolled back on failure)

    func updateName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await mutate({ $0.fullName = trimmed.isEmpty ? nil : trimmed }) {
            try await self.profiles.update(fullName: trimmed.isEmpty ? nil : trimmed)
        }
    }

    /// Upload a new photo and point the profile at it; the old object is
    /// deleted after the switch, best effort.
    func updateAvatar(jpeg: Data, preview: UIImage) async -> Bool {
        guard let previous = profile else { return false }
        do {
            let path = try await profiles.uploadAvatar(jpeg: jpeg)
            profile?.avatarPath = path
            if let url = avatarURL { AvatarImageCache.shared.store(preview, for: url) }
            do {
                try await profiles.update(avatarPath: path)
            } catch {
                profile = previous
                await profiles.removeAvatar(path)
                return false
            }
            if let old = previous.avatarPath, !old.isEmpty { await profiles.removeAvatar(old) }
            await refreshTabAvatar()
            return true
        } catch {
            return false
        }
    }

    func removeAvatar() async -> Bool {
        guard let old = profile?.avatarPath, !old.isEmpty else { return true }
        let ok = await mutate({ $0.avatarPath = nil }) { try await self.profiles.update(avatarPath: nil) }
        if ok { await profiles.removeAvatar(old) }
        return ok
    }

    private func mutate(_ change: (inout Profile) -> Void, write: () async throws -> Void) async -> Bool {
        guard var next = profile else { return false }
        let previous = next
        change(&next)
        profile = next
        do {
            try await write()
            await refreshTabAvatar()
            return true
        } catch {
            profile = previous
            return false
        }
    }

    /// Render the tab-bar avatar: the photo when it loads, else initials.
    func refreshTabAvatar() async {
        guard isSignedIn else { tabAvatar = nil; return }
        var photo: UIImage?
        if let url = avatarURL { photo = await AvatarImageCache.shared.image(for: url) }
        tabAvatar = AvatarImageCache.tabImage(photo: photo, initials: initials)
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

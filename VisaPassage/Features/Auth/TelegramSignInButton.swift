import AuthenticationServices
import SwiftUI

/// "Continue with Telegram". Supabase has no Telegram provider, so the web app
/// brokers it: an `ASWebAuthenticationSession` opens
/// `visapassage.com/auth/telegram/start?client=ios`, Telegram's consent page
/// signs the user in, and the server verifies the signature and returns
/// `visapassage://auth/callback?token_hash=…&type=magiclink`. The one-time token
/// is redeemed with `verifyOTP`, and `AuthStore` picks up the new session.
/// Hidden unless `AppConfig.hasTelegramSignIn` (Info.plist `TelegramSignIn = YES`).
struct TelegramSignInButton: View {
    var title: String = "Continue with Telegram"
    @Environment(AuthStore.self) private var auth
    @State private var session: ASWebAuthenticationSession?
    private let anchor = PresentationAnchor()

    var body: some View {
        AuthProviderButton(title: LocalizedStringKey(title), action: start) {
            Image("telegram-logo")
                .resizable()
                .scaledToFit()
        }
    }

    private func start() {
        var components = URLComponents(url: AppConfig.webBaseURL.appendingPathComponent("auth/telegram/start"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "client", value: "ios"), URLQueryItem(name: "intent", value: "login")]
        guard let url = components?.url else { return }

        let webSession = ASWebAuthenticationSession(url: url, callbackURLScheme: AppConfig.urlScheme) { callback, error in
            Task { @MainActor in
                session = nil
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return }
                guard let callback,
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
                    auth.errorMessage = String(localized: "Telegram sign-in failed. Please try again.")
                    return
                }
                if items.contains(where: { $0.name == "error" }) {
                    auth.errorMessage = String(localized: "Telegram sign-in isn't available right now. Please try another method.")
                    return
                }
                guard let tokenHash = items.first(where: { $0.name == "token_hash" })?.value else {
                    auth.errorMessage = String(localized: "Telegram sign-in failed. Please try again.")
                    return
                }
                do {
                    try await AuthService().signInWithTelegram(tokenHash: tokenHash)
                } catch {
                    auth.errorMessage = String(localized: "Telegram sign-in failed. Please try again.")
                }
            }
        }
        webSession.presentationContextProvider = anchor
        // Ephemeral: no cookies shared with Safari, and the session ends with the sheet.
        webSession.prefersEphemeralWebBrowserSession = true
        session = webSession
        webSession.start()
    }
}

/// Presents the auth session over the key window.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

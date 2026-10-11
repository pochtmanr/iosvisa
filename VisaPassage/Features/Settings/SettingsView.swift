import SwiftUI
import UIKit

/// The Settings tab: account (sign in, or who you are and log out), language,
/// and links to the website. Profile editing, passports and account deletion
/// arrive in IOS-06.
struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section("Preferences") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        LabeledContent("Language", value: AppLocale.current.displayName)
                    }
                    .foregroundStyle(Theme.ink)
                }

                Section("VisaPassage") {
                    webLink("Open the website", path: "", icon: "globe")
                    webLink("How we verify data", path: "/how-we-verify", icon: "checkmark.seal")
                    webLink("Privacy", path: "/privacy", icon: "hand.raised")
                    webLink("Terms", path: "/terms", icon: "doc.text")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                } footer: {
                    Text("No visa approval guarantees — official decisions prevail.")
                }
            }
            .navigationTitle("Settings")
        }
        .floatingSheet(isPresented: $showSignIn) { AuthSheet() }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if auth.isSignedIn {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(auth.profile?.displayName ?? auth.userEmail ?? "")
                        .typography(.title).foregroundStyle(Theme.ink)
                    if auth.profile?.displayName != nil, let email = auth.userEmail {
                        Text(verbatim: email).typeRole(.monoSm).foregroundStyle(Theme.textBody)
                    }
                }
                .padding(.vertical, Spacing.xs)
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button { showSignIn = true } label: {
                    Label("Sign in", systemImage: "person.crop.circle")
                }
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private func webLink(_ title: LocalizedStringKey, path: String, icon: String) -> some View {
        Button {
            openURL(AppLocale.current.webURL(path: path))
        } label: {
            Label(title, systemImage: icon)
        }
        .foregroundStyle(Theme.ink)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

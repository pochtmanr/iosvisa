import SwiftUI
import UIKit

/// The Account tab: a profile card with a photo banner (who you are, or an
/// invitation to sign in) heading a standard inset-grouped settings list:
/// sharing, the website's pages in an in-app Safari view, and the account
/// actions. Passports are managed from Home and Explore, so they don't live here.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var showSignIn = false
    @State private var showEditName = false
    @State private var confirmLogOut = false
    @State private var signingOut = false
    @State private var webPage: WebPage?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TabHeader(title: Text("Account"))
                        .tabHeaderRow()
                }
                Section {
                    AccountHero(onSignIn: { showSignIn = true },
                                onEditName: { showEditName = true })
                        .listRowInsets(EdgeInsets())
                }
                spreadTheWord
                about
                if auth.isSignedIn { accountActions }
                #if DEBUG
                developer
                #endif
                Section {
                    LabeledContent("Version", value: Self.version)
                } footer: {
                    Text("No visa approval guarantees — official decisions prevail.")
                }
            }
            .listStyle(.insetGrouped)
            .toolbar(.hidden, for: .navigationBar)
        }
        .floatingSheet(isPresented: $showSignIn, surface: .glass) { AuthSheet() }
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .centredDialog(isPresented: $showEditName, maxWidth: 400) { close in
            EditNameDialog(initial: auth.profile?.displayName ?? auth.oauthName ?? "", close: close)
        }
        .confirmationDialog("Log out of VisaPassage?", isPresented: $confirmLogOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task {
                    signingOut = true
                    SpotlightIndexer.removeAll()
                    await auth.signOut()
                    signingOut = false
                }
            }
        } message: {
            Text("Your visas stay in your account. Sign in again any time to see them.")
        }
    }

    // MARK: - Sections

    private var spreadTheWord: some View {
        Section("Spread the word") {
            if let review = AppConfig.appStoreReviewURL {
                Button { openURL(review) } label: {
                    Label("Rate VisaPassage", systemImage: "star")
                }
                .foregroundStyle(Theme.ink)
            }
            ShareLink(
                item: AppLocale.current.webURL(path: ""),
                message: Text("Visa rules for every passport, with sources.")
            ) {
                Label("Share VisaPassage", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(Theme.ink)
        }
    }

    private var about: some View {
        Section("VisaPassage") {
            webLink("Open the website", path: "", icon: "globe")
            webLink("About us", path: "/about", icon: "info.circle")
            webLink("How we verify data", path: "/how-we-verify", icon: "checkmark.seal")
            webLink("Blog", path: "/blog", icon: "newspaper")
            webLink("Contact us", path: "/contact", icon: "envelope")
            webLink("Privacy", path: "/privacy", icon: "hand.raised")
            webLink("Terms", path: "/terms", icon: "doc.text")
        }
    }

    private var accountActions: some View {
        Section {
            Button { confirmLogOut = true } label: {
                HStack {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                    if signingOut { ProgressView() }
                }
            }
            .foregroundStyle(Theme.ink)
            .disabled(signingOut)
            NavigationLink {
                DeleteAccountView()
            } label: {
                Label("Delete account", systemImage: "trash")
                    .foregroundStyle(StatusHue.red.solid)
            }
        }
    }

    #if DEBUG
    private var developer: some View {
        Section {
            NavigationLink {
                DesignLabView()
            } label: {
                Label {
                    Text(verbatim: "Design Lab")
                } icon: {
                    Image(systemName: "paintpalette")
                }
            }
            .foregroundStyle(Theme.ink)
        } header: {
            Text(verbatim: "Developer")
        }
    }
    #endif

    // MARK: - Helpers

    private func webLink(_ title: LocalizedStringKey, path: String, icon: String) -> some View {
        Button {
            webPage = WebPage(url: AppLocale.current.webURL(path: path))
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

// MARK: - Edit name

/// A centred dialog for the display name (`profiles.full_name`).
private struct EditNameDialog: View {
    @Environment(AuthStore.self) private var auth
    let initial: String
    let close: () -> Void

    @State private var name = ""
    @State private var saving = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Display name").typography(.title).foregroundStyle(Theme.ink)
                Text("Used in greetings and on your checklists.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
            }
            TextField("Your name", text: $name)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, Spacing.lg)
                .frame(height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width))
            if failed {
                Text("We couldn't save that change. Please try again.")
                    .typography(.xs).foregroundStyle(StatusHue.red.solid)
            }
            HStack(spacing: Spacing.sm) {
                SecondaryButton(title: "Cancel", action: close)
                PrimaryButton(title: "Save", icon: nil, loading: saving, action: save)
            }
        }
        .padding(Spacing.xl)
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let ok = await auth.updateName(name)
            saving = false
            if ok { close() } else { failed = true }
        }
    }
}

import SwiftUI
import UIKit

/// The Settings tab: account (sign in, or who you are, log out and delete),
/// your passports (synced with the account when signed in), language, rating
/// and sharing the app, and the website's pages in an in-app Safari view.
struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(PassportPreference.self) private var passports
    @Environment(CountryStore.self) private var catalog
    @Environment(PassportStrengthStore.self) private var strength
    @Environment(\.openURL) private var openURL

    @State private var showSignIn = false
    @State private var showPassports = false
    @State private var webPage: WebPage?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                passportsSection

                Section("Preferences") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        LabeledContent("Language", value: AppLocale.current.displayName)
                    }
                    .foregroundStyle(Theme.ink)
                }

                Section {
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
                } header: {
                    Text("Spread the word")
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
            .task { await strength.loadIfNeeded() }
        }
        .floatingSheet(isPresented: $showSignIn, surface: .glass) { AuthSheet() }
        .sheet(isPresented: $showPassports) { PassportsSheet() }
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    // MARK: - Account

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
                Button {
                    Task {
                        SpotlightIndexer.removeAll()
                        await auth.signOut()
                    }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundStyle(Theme.ink)
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Label("Delete account", systemImage: "trash")
                        .foregroundStyle(StatusHue.red.solid)
                }
            } else {
                Button { showSignIn = true } label: {
                    Label("Sign in", systemImage: "person.crop.circle")
                }
                .foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: - Passports

    private var passportsSection: some View {
        Section {
            ForEach(passports.passports, id: \.self) { iso in
                passportRow(iso)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { passports.remove(iso) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        if passports.primary != iso {
                            Button { passports.makePrimary(iso) } label: {
                                Label("Make primary", systemImage: "star")
                            }
                            .tint(Theme.accent)
                        }
                    }
            }
            Button { showPassports = true } label: {
                Label(passports.passports.isEmpty ? "Add a passport" : "Edit passports",
                      systemImage: passports.passports.isEmpty ? "plus" : "pencil")
            }
            .foregroundStyle(Theme.ink)
        } header: {
            Text("My passports")
        } footer: {
            Text(auth.isSignedIn
                 ? "Synced with your account on visapassage.com."
                 : "Saved on this device. Sign in to keep them in sync with the website.")
        }
    }

    private func passportRow(_ iso: String) -> some View {
        let name = catalog.name(forISO2: iso) ?? iso
        let rank = strength.rank(for: iso, slugged: slugged)
        let url = passportURL(iso)
        return HStack(spacing: Spacing.md) {
            CountryFlag(iso2: iso, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).typography(.body).foregroundStyle(Theme.ink)
                HStack(spacing: Spacing.sm) {
                    if passports.primary == iso {
                        Text("Primary").typography(.xs).foregroundStyle(Theme.textBody)
                    }
                    if let rank {
                        Text("Rank #\(rank.rank)").typography(.xs).foregroundStyle(Theme.textSoft)
                    }
                }
            }
            Spacer()
            if let rank {
                ShareCardButton(url: url, renderID: "\(iso)-\(rank.rank)") {
                    PassportRankShareCard(iso2: iso, name: name, rank: rank, url: url)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.ink)
                .simultaneousGesture(TapGesture().onEnded {
                    SpotlightIndexer.indexPassport(iso, name: name, rank: rank.rank, url: url)
                })
            }
        }
        .padding(.vertical, 2)
    }

    private var slugged: Set<String> {
        Set(catalog.countries.filter { $0.slug != nil }.map { $0.iso2.uppercased() })
    }

    private func passportURL(_ iso: String) -> URL {
        guard let slug = catalog.country(iso)?.slug else { return AppLocale.current.webURL(path: "/passports") }
        return AppLocale.current.webURL(path: "/passports/\(slug)")
    }

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

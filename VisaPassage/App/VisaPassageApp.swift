import SwiftUI
import GoogleSignIn
import CoreSpotlight

@main
struct VisaPassageApp: App {
    @State private var auth = AuthStore()
    @State private var router = DeepLinkRouter()
    @State private var countries = CountryStore()
    @State private var passports = PassportPreference()
    @State private var explore = ExploreSelection()
    @State private var requirements = RequirementsStore()
    @State private var strength = PassportStrengthStore()
    @State private var tabs = TabRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(router)
                .environment(countries)
                .environment(passports)
                .environment(explore)
                .environment(requirements)
                .environment(strength)
                .environment(tabs)
                .tint(Theme.accent)
                .task { auth.start() }
                .task { await countries.loadIfNeeded() }
                .onOpenURL { url in
                    // Let the Google SDK claim its own OAuth redirect first.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    router.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url) }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        router.handleSpotlight(identifier: id)
                    }
                }
        }
    }
}

import SwiftUI
import GoogleSignIn

@main
struct VisaPilotApp: App {
    @State private var auth = AuthStore()
    @State private var router = DeepLinkRouter()
    @State private var countries = CountryStore()
    @State private var discovery = DiscoverySelection()
    @State private var tabs = TabRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(router)
                .environment(countries)
                .environment(discovery)
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
        }
    }
}

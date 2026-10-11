import SwiftUI

/// The tab shell. Same four places as the web phone tab bar, with SF Symbols
/// standing in for its line icons (house, compass, stack, gear).
struct MainTabView: View {
    @Environment(PassportPreference.self) private var passports
    @Environment(ExploreSelection.self) private var explore
    @Environment(DeepLinkRouter.self) private var router
    @Environment(TabRouter.self) private var tabs
    @Environment(CountryStore.self) private var catalog
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var tabs = tabs
        TabView(selection: $tabs.selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MainTab.home)

            ExploreView()
                .tabItem { Label("Explore", systemImage: "safari") }
                .tag(MainTab.explore)

            MyVisasView()
                .tabItem { Label("My visas", systemImage: "square.stack") }
                .tag(MainTab.visas)

            ProfileView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .onChange(of: router.pending) { _, newValue in handle(newValue) }
        .onChange(of: catalog.countries.count) { handle(router.pending) }
        // Passports follow the account while signed in: pull on sign-in,
        // push every local edit.
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn { await PassportSync().pull(into: passports) }
        }
        .onChange(of: passports.passports) { _, list in
            guard auth.isSignedIn else { return }
            Task { await PassportSync().push(list) }
        }
        .onAppear { handle(router.pending) }
    }

    /// Act on an in-app deep link. Site links name countries by slug, so they
    /// wait for the catalog; auth callbacks are RootView's.
    private func handle(_ route: DeepLinkRouter.Route?) {
        guard let route else { return }
        switch route {
        case .visaChecker(let codes, let destination):
            // Take its passports (up to two), open Explore, and show the
            // destination's panel when it names one.
            if !codes.isEmpty { passports.set(codes) }
            if let destination { explore.show(destination: destination) }
            tabs.selection = .explore

        case .corridor(let fromSlug, let toSlug):
            guard let from = iso2(for: fromSlug), let to = iso2(for: toSlug) else { return }
            explore.pendingRoute = .corridor(from: from, to: to)
            tabs.selection = .explore

        case .destination(let slug):
            guard let to = iso2(for: slug) else { return }
            explore.pendingRoute = .destination(to)
            tabs.selection = .explore

        case .passport(let slugOrISO):
            // The ranking lives under Explore (4 tabs), so passport pages open there.
            guard let iso = iso2(for: slugOrISO) else { return }
            explore.pendingPassport = iso
            tabs.selection = .explore

        case .tracker:
            // TODO IOS-05: open the tracker by id.
            tabs.selection = .visas

        case .authCallback:
            return

        case .unknown:
            break
        }
        router.consume()
    }

    /// Resolve a site slug (or an ISO2 code from Spotlight) against the
    /// catalog. Nil while the catalog is still loading.
    private func iso2(for slugOrCode: String) -> String? {
        let key = slugOrCode.lowercased()
        return catalog.countries.first { $0.slug?.lowercased() == key }?.iso2.uppercased()
            ?? catalog.country(slugOrCode)?.iso2.uppercased()
    }
}

import SwiftUI

/// The tab shell. Same four places as the web phone tab bar, with SF Symbols
/// standing in for its line icons (house, compass, stack, gear).
struct MainTabView: View {
    @Environment(DiscoverySelection.self) private var selection
    @Environment(DeepLinkRouter.self) private var router
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        @Bindable var tabs = tabs
        TabView(selection: $tabs.selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MainTab.home)

            DiscoverView()
                .tabItem { Label("Explore", systemImage: "safari") }
                .tag(MainTab.explore)

            MyVisasView()
                .tabItem { Label("My visas", systemImage: "square.stack") }
                .tag(MainTab.visas)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .onChange(of: router.pending) { _, newValue in handle(newValue) }
        .onAppear { handle(router.pending) }
    }

    /// Route a visa-checker deep link: hydrate the selection and open Explore.
    private func handle(_ route: DeepLinkRouter.Route?) {
        guard case .visaChecker(let passports, let destination)? = route else { return }
        selection.apply(passports: passports, destination: destination)
        tabs.selection = .explore
        router.consume()
    }
}

import SwiftUI

/// The signed-in shell. Tabs mirror the web app's primary destinations.
/// Most tabs are placeholders in M0 and get built out in later milestones.
struct MainTabView: View {
    @Environment(DiscoverySelection.self) private var selection
    @Environment(DeepLinkRouter.self) private var router
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        @Bindable var tabs = tabs
        TabView(selection: $tabs.selection) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MainTab.home)

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "globe") }
                .tag(MainTab.discover)

            ApplicationsListView()
                .tabItem { Label("Applications", systemImage: "doc.text") }
                .tag(MainTab.applications)

            ProfileHomeView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(MainTab.profile)
        }
        .onChange(of: router.pending) { _, newValue in handle(newValue) }
        .onAppear { handle(router.pending) }
    }

    /// Route a discovery deep link: hydrate the selection and switch to Discover.
    private func handle(_ route: DeepLinkRouter.Route?) {
        guard case .visaChecker(let passports, let destination)? = route else { return }
        selection.apply(passports: passports, destination: destination)
        tabs.selection = .discover
        router.consume()
    }
}

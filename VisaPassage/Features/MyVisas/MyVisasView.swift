import SwiftUI

/// The My visas tab (`/app/trackers`): every open visa, most urgent first, a
/// "Find a visa" pill, then the history, on the same inset grouped list as the
/// other tabs. The only tab that needs an account: guests see a sign-in gate.
struct MyVisasView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TabRouter.self) private var tabs
    @Environment(TrackerStore.self) private var store

    @State private var showSignIn = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    TabHeader(title: Text("My visas"))
                        .tabHeaderRow()
                }
                if auth.isSignedIn { list } else { block { signInGate } }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Spacing.xl)
            .scrollContentBackground(.hidden)
            .background(Theme.groupedBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.load() }
            .trackerDestinations()
            .catalogDestinations()
            .passportDestinations()
            .onAppear(perform: consumePending)
            .onChange(of: tabs.pendingTracker) { consumePending() }
        }
        .floatingSheet(isPresented: $showSignIn, surface: .glass) { AuthSheet() }
    }

    private func consumePending() {
        guard let id = tabs.pendingTracker, auth.isSignedIn else { return }
        tabs.pendingTracker = nil
        path.append(TrackerRoute.detail(id))
    }

    @ViewBuilder
    private var list: some View {
        let today = DashboardState.today()
        let open = DashboardState.rankOpen(
            store.trackers.filter { !$0.tracker.isArchived && !$0.tracker.status.isClosed }, today: today)
        let history = store.state.history

        if !store.loaded && store.loading {
            block { ProgressView().frame(maxWidth: .infinity) }
        } else if store.failed && !store.loaded {
            block { CatalogStateCard(kind: .failed, retry: { Task { await store.load() } }) }
        } else {
            if open.isEmpty && history.isEmpty {
                block {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("No visas yet").font(.custom("Geist-Medium", size: 15)).foregroundStyle(Theme.ink)
                        Text("Find a visa on the map and add it. Its document checklist appears here.")
                            .font(.custom("Geist-Regular", size: 14))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: Hairline.width, dash: [4, 3])))
                }
            }

            if !open.isEmpty {
                block { MyVisasSection(title: String(localized: "In progress"), trackers: open) }
            }

            block {
                Button { tabs.selection = .explore } label: {
                    HStack(spacing: Spacing.sm) {
                        Text("Find a visa")
                        CardArrow().frame(width: 16, height: 16)
                    }
                    .font(.custom("Geist-Medium", size: 14))
                    .foregroundStyle(Theme.inkInverse)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressShrinkStyle())
            }

            if !history.isEmpty {
                block { TrackerHistoryList(trackers: history) }
            }
        }
    }

    /// One block of the screen as a bare list section: no row inset, card or
    /// separator, so the cards keep their own look on the grouped ground.
    private func block(@ViewBuilder _ content: () -> some View) -> some View {
        Section {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var signInGate: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Image(systemName: "person.crop.circle").font(.system(size: 28)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Sign in to track your visas").typography(.title).foregroundStyle(Theme.ink)
                    Text("Your trackers are saved to your VisaPassage account. Everything else in the app works without one.")
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                }
                PrimaryButton(title: "Sign in") { showSignIn = true }
            }
        }
    }
}

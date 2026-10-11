import Foundation
import Observation

/// The four tabs. They mirror the web phone tab bar (`AppTabBar.tsx`):
/// Home, Explore, My visas, Account.
enum MainTab: Hashable, Sendable { case home, explore, visas, account }

/// Shared, observable tab selection so any screen can switch tabs (e.g. the
/// Home "Explore destinations" card jumps to Explore). Injected at the app root
/// and bound by `MainTabView`.
@MainActor
@Observable
final class TabRouter {
    var selection: MainTab = .home
    /// A tracker to open in My visas (`/app/trackers/{id}` links), consumed once.
    var pendingTracker: UUID?

    init() {
        #if DEBUG
        // Screenshots: `-debug.tab explore`.
        switch UserDefaults.standard.string(forKey: "debug.tab") {
        case "explore": selection = .explore
        case "visas": selection = .visas
        case "account", "settings": selection = .account
        default: break
        }
        #endif
    }
}

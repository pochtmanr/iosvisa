import Foundation
import Observation

/// The four tabs. They mirror the web phone tab bar (`AppTabBar.tsx`):
/// Home, Explore, My visas, Settings.
enum MainTab: Hashable, Sendable { case home, explore, visas, settings }

/// Shared, observable tab selection so any screen can switch tabs (e.g. the
/// Home "Explore destinations" card jumps to Explore). Injected at the app root
/// and bound by `MainTabView`.
@MainActor
@Observable
final class TabRouter {
    var selection: MainTab = .home
}

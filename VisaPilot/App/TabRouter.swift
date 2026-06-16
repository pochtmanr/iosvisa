import Foundation
import Observation

/// The signed-in shell's four tabs.
enum MainTab: Hashable, Sendable { case home, discover, applications, profile }

/// Shared, observable tab selection so any screen can switch tabs (e.g. the
/// dashboard's "Explore destinations" CTA jumps to Discover). Injected at the
/// app root and bound by `MainTabView`.
@MainActor
@Observable
final class TabRouter {
    var selection: MainTab = .home
}

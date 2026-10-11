import Foundation

/// Decides when to ask for an App Store review: after a tracker is completed,
/// or once three different corridors have been opened. Asks at most once per
/// app version. The host view calls `@Environment(\.requestReview)` when a
/// method here returns true.
struct ReviewPrompter {
    static let viewedKey = "review.corridorsViewed"
    static let askedVersionKey = "review.askedVersion"
    static let corridorThreshold = 3

    var defaults: UserDefaults = .standard
    var version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    /// Record a corridor view. True when this view should trigger the prompt.
    func corridorViewed(from: String, to: String) -> Bool {
        let id = "\(from.uppercased())-\(to.uppercased())"
        var viewed = defaults.stringArray(forKey: Self.viewedKey) ?? []
        if !viewed.contains(id) {
            viewed.append(id)
            // Only the count matters; keep the list short.
            defaults.set(Array(viewed.suffix(20)), forKey: Self.viewedKey)
        }
        guard viewed.count >= Self.corridorThreshold else { return false }
        return claim()
    }

    /// A tracker reached its final step (IOS-05 calls this). True to prompt.
    func trackerCompleted() -> Bool { claim() }

    /// Takes this version's single prompt, if it hasn't been used.
    private func claim() -> Bool {
        guard defaults.string(forKey: Self.askedVersionKey) != version else { return false }
        defaults.set(version, forKey: Self.askedVersionKey)
        return true
    }
}

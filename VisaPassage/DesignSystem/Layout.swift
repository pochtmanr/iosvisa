import SwiftUI

/// Spacing, radius, and hairline tokens from `tokens/spacing.css`.
/// The hairline structure (1px borders, 24px cards, no rest shadow) is the
/// signature of the brand.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    /// Signature card radius.
    static let card: CGFloat = 24
    static let pill: CGFloat = 999
}

enum Hairline {
    /// 1px hairline — rendered at the device's native pixel where possible.
    static let width: CGFloat = 1
}

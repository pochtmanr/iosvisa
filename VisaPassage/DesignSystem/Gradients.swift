import SwiftUI

/// Brand accent gradient — a warm pink → orange sweep used sparingly for the
/// welcome headline accent word and the intro's down-arrow button. It echoes the
/// "start here" energy of a delightful first impression while the rest of the app
/// stays on the calm ink-on-paper spine.
enum BrandGradient {
    private static let pink = Color(hex: 0xF0508C)
    private static let orange = Color(hex: 0xF5A623)

    /// Leading → trailing sweep for tinting text and small shapes.
    static let accent = LinearGradient(
        colors: [pink, orange],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Top-left → bottom-right sweep, better for filling circular/area shapes.
    static let accentDiagonal = LinearGradient(
        colors: [pink, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

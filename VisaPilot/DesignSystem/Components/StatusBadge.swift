import SwiftUI

/// Soft status badge — tinted background + readable foreground in the given
/// hue. Used for visa-status and application-status chips. Saturated color is
/// reserved for these semantics only.
struct StatusBadge: View {
    let text: String
    let hue: StatusHue
    var icon: String? = nil

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(text).typeRole(.eyebrow).textCase(.uppercase)
        }
        .foregroundStyle(hue.softFg)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(hue.softBg)
        .clipShape(Capsule())
    }
}

/// Solid status dot (e.g. map legend, list leading indicator).
struct StatusDot: View {
    let hue: StatusHue
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(hue.solid).frame(width: size, height: size)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        StatusBadge(text: "Visa-free", hue: .green, icon: "checkmark")
        StatusBadge(text: "eVisa", hue: .blue)
        StatusBadge(text: "Visa required", hue: .yellow)
        StatusBadge(text: "No admission", hue: .red)
        StatusBadge(text: "Processing", hue: .orange)
    }
    .padding()
    .background(Theme.bg)
}

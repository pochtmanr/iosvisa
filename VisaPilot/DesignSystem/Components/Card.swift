import SwiftUI

/// Signature VisaPilot card: paper surface, 1px hairline border, 24px radius,
/// no rest shadow. Compose content inside.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.xl
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("United Kingdom").typography(.title)
                Text("ETA · may be eligible").typography(.sm).foregroundStyle(Theme.textBody)
            }
        }
    }
    .padding()
    .background(Theme.bg)
}

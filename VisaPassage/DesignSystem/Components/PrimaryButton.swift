import SwiftUI

/// Ink-filled primary action. Press shrinks slightly (the brand's calm
/// hover-lift / press-shrink motion). A `loading` state swaps the label for a
/// spinner and disables interaction.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var icon: String? = "arrow.right"
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if loading {
                    ProgressView().tint(Theme.accentContrast)
                } else {
                    Text(title).typography(.sm)
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .medium)) }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Theme.accentContrast)
            .background(Theme.accent)
            .clipShape(Capsule(style: .continuous))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressShrinkStyle())
        .disabled(!enabled || loading)
    }
}

/// Secondary action: hairline outline, ink text.
struct SecondaryButton: View {
    let title: LocalizedStringKey
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .medium)) }
                Text(title).typography(.sm)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Theme.ink)
            .background(Theme.surfaceCard)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
        }
        .buttonStyle(PressShrinkStyle())
    }
}

/// Calm press feedback: a subtle scale-down, no bounce.
struct PressShrinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        PrimaryButton(title: "Continue") {}
        PrimaryButton(title: "Working…", loading: true) {}
        SecondaryButton(title: "Back", icon: "chevron.left") {}
    }
    .padding()
    .background(Theme.bg)
}

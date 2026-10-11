import SwiftUI

/// One sign-in option on the sign-in card (Apple, Google, Email). All three
/// share this label so the text size, icon box and height match exactly; the
/// surface is Liquid Glass on iOS 26 and a frosted material before it.
struct AuthProviderButton<Icon: View>: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                icon()
                    .frame(width: AuthProviderButtonMetrics.iconSize, height: AuthProviderButtonMetrics.iconSize)
                Text(title).typography(.bodyLg)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressShrinkStyle())
        .glassCapsule()
    }
}

extension AuthProviderButton where Icon == AuthSymbol {
    /// An SF Symbol icon, sized to fill the shared icon box.
    init(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(title: title, action: action) { AuthSymbol(name: systemImage) }
    }
}

enum AuthProviderButtonMetrics {
    static let iconSize: CGFloat = 20
}

/// An SF Symbol scaled to the auth button's icon box.
struct AuthSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
    }
}

extension View {
    /// A glass capsule surface: Liquid Glass on iOS 26, frosted material with a
    /// hairline rim and a soft top highlight on earlier systems.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Theme.border.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: Hairline.width
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }

    /// A glass circle (icon buttons such as the sheet's close button).
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border.opacity(0.6), lineWidth: Hairline.width))
        }
    }
}

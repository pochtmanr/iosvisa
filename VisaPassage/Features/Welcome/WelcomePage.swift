import SwiftUI

/// One welcome page, built like the landing's photo cards: a full-bleed photo
/// under an ink scrim, the step's illustration floating in the middle, and the
/// numbered step text at the bottom (white on the scrim, so it reads the same
/// in light and dark).
struct WelcomePage<Art: View>: View {
    let number: Int
    let photo: String
    /// Which part of the photo survives the portrait crop.
    var crop: Alignment = .center
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Space reserved under the text for the flow's fixed controls.
    var bottomInset: CGFloat
    @ViewBuilder let art: () -> Art

    var body: some View {
        ZStack {
            photoLayer
            scrim

            VStack(spacing: 0) {
                // Room for the flow's top bar (logo + Skip).
                Spacer().frame(height: 64)
                art()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                text
                Spacer().frame(height: bottomInset)
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    private var photoLayer: some View {
        GeometryReader { geo in
            Image(photo)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height, alignment: crop)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var scrim: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.4),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .containerRelativeFrame(.vertical) { height, _ in height * 0.58 }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: String(format: "%02d", number))
                .font(.custom("GeistMono-Regular", size: 26))
                .tracking(-0.5)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text(title)
                .typography(.h1)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .typography(.bodyLg)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

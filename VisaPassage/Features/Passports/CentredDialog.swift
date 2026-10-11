import SwiftUI

extension View {
    /// Presents `content` as a centred card over a dimmed backdrop: the web's
    /// `.center-dialog` (fade + lift), at every width. Never a bottom sheet.
    /// Tap the backdrop to close. `content` gets the item and a close action.
    func centredDialog<Item, Content: View>(
        item: Binding<Item?>,
        maxWidth: CGFloat = 440,
        fillsHeight: Bool = false,
        surface: FloatingSheetSurface = .solid,
        @ViewBuilder content: @escaping (Item, _ close: @escaping () -> Void) -> Content
    ) -> some View {
        modifier(CentredDialogModifier(item: item, maxWidth: maxWidth, fillsHeight: fillsHeight,
                                       surface: surface, card: content))
    }

    /// The `Bool` form of `centredDialog(item:)`.
    func centredDialog<Content: View>(
        isPresented: Binding<Bool>,
        maxWidth: CGFloat = 440,
        fillsHeight: Bool = false,
        surface: FloatingSheetSurface = .solid,
        @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Content
    ) -> some View {
        let item = Binding<Bool?>(
            get: { isPresented.wrappedValue ? true : nil },
            set: { isPresented.wrappedValue = $0 != nil }
        )
        return centredDialog(item: item, maxWidth: maxWidth, fillsHeight: fillsHeight, surface: surface) { _, close in
            content(close)
        }
    }
}

/// Hosts the card in a transparent full-screen cover, so it sits above the
/// navigation and tab bars. The cover appears without animation; the backdrop
/// fade and the card's lift are animated here.
private struct CentredDialogModifier<Item, Card: View>: ViewModifier {
    @Binding var item: Item?
    let maxWidth: CGFloat
    let fillsHeight: Bool
    let surface: FloatingSheetSurface
    let card: (Item, @escaping () -> Void) -> Card

    @State private var shown: Item?
    @State private var coverShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coverShown) {
                if let shown {
                    CentredDialogHost(maxWidth: maxWidth, fillsHeight: fillsHeight, surface: surface, close: { item = nil },
                                      onClosed: { setCover(false) }, isPresented: item != nil) { close in
                        card(shown, close)
                    }
                    .presentationBackground(.clear)
                }
            }
            .onChange(of: item != nil) { _, presented in
                if presented, let item {
                    shown = item
                    setCover(true)
                }
            }
    }

    private func setCover(_ visible: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = visible }
    }
}

private struct CentredDialogHost<Content: View>: View {
    let maxWidth: CGFloat
    let fillsHeight: Bool
    let surface: FloatingSheetSurface
    let close: () -> Void
    let onClosed: () -> Void
    let isPresented: Bool
    @ViewBuilder let content: (_ close: @escaping () -> Void) -> Content

    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let motion = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.28)

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            ZStack {
                Color.black
                    .opacity(visible ? 0.4 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("Close"))

                content(dismiss)
                    .frame(maxWidth: min(maxWidth, geo.size.width - 32))
                    .frame(maxHeight: fillsHeight ? min(640, geo.size.height - 48) : nil)
                    .modifier(DialogSurface(surface: surface, shape: shape))
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
                    .opacity(visible ? 1 : 0)
                    .scaleEffect(visible || reduceMotion ? 1 : 0.97)
                    .offset(y: visible || reduceMotion ? 0 : 12)
                    .accessibilityAddTraits(.isModal)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { withAnimation(motion) { visible = true } }
        .onChange(of: isPresented) { _, presented in
            if !presented { animateOut() }
        }
    }

    private func dismiss() {
        close()
    }

    private func animateOut() {
        withAnimation(motion) { visible = false } completion: { onClosed() }
    }
}

/// The card's ground: the page colour with a hairline, or Liquid Glass
/// (`.regularMaterial` before iOS 26).
private struct DialogSurface: ViewModifier {
    let surface: FloatingSheetSurface
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        switch surface {
        case .solid:
            content
                .background(Theme.bg, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.border, lineWidth: Hairline.width))
        case .glass:
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content
                    .background(.regularMaterial, in: shape)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: Hairline.width))
            }
        }
    }
}

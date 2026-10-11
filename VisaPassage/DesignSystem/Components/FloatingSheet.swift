import SwiftUI
import UIKit

extension View {
    /// Presents `content` as a floating card: inset from the screen edges, with
    /// corners concentric with the display's, over a dimmed backdrop. Tap the
    /// backdrop or swipe the card down to dismiss. Content can close it with
    /// `@Environment(\.dismissFloatingSheet)`.
    func floatingSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(FloatingSheetModifier(isPresented: isPresented, sheet: content))
    }
}

extension EnvironmentValues {
    /// Closes the enclosing floating sheet (animated). No-op outside one.
    @Entry var dismissFloatingSheet: () -> Void = {}
}

/// Hosts the card in a transparent full-screen cover, so it sits above the tab
/// bar and navigation chrome. The cover itself appears without animation; the
/// backdrop fade and card slide are animated here instead.
private struct FloatingSheetModifier<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheet: () -> Sheet
    @State private var coverShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coverShown) {
                FloatingSheetHost(isPresented: $isPresented, onClosed: { setCover(false) }, content: sheet)
                    .presentationBackground(.clear)
            }
            .onChange(of: isPresented) { _, presented in
                if presented { setCover(true) }
            }
    }

    private func setCover(_ shown: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = shown }
    }
}

private struct FloatingSheetHost<Content: View>: View {
    @Binding var isPresented: Bool
    let onClosed: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var cardShown = false
    @State private var drag: CGFloat = 0

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.88)

    var body: some View {
        GeometryReader { geo in
            let homeIndicator = geo.safeAreaInsets.bottom > 0
            let inset: CGFloat = homeIndicator ? 8 : 12
            let radius = homeIndicator
                ? max(DisplayCorner.estimatedRadius(screenWidth: geo.size.width) - inset, Radius.card)
                : Radius.card
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(cardShown ? 0.4 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityLabel(Text("Close"))
                    .accessibilityAddTraits(.isButton)

                if cardShown {
                    content()
                        .frame(maxWidth: .infinity)
                        .background(Theme.bg, in: shape)
                        .overlay(shape.strokeBorder(Theme.border, lineWidth: Hairline.width))
                        .clipShape(shape)
                        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
                        .padding(.horizontal, inset)
                        .padding(.bottom, inset)
                        .offset(y: drag)
                        .gesture(dragToDismiss)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .environment(\.dismissFloatingSheet, { close() })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear { withAnimation(spring) { cardShown = true } }
        .onChange(of: isPresented) { _, presented in
            if !presented { animateOut() }
        }
    }

    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                // Free downward, rubber-band upward.
                drag = value.translation.height > 0 ? value.translation.height : value.translation.height / 6
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    close()
                } else {
                    withAnimation(spring) { drag = 0 }
                }
            }
    }

    private func close() {
        if isPresented { isPresented = false } else { animateOut() }
    }

    private func animateOut() {
        withAnimation(spring, completionCriteria: .logicallyComplete) {
            cardShown = false
        } completion: {
            drag = 0
            onClosed()
        }
    }
}

/// The display's corner radius, estimated from the screen width (there is no
/// public API for it). Face ID iPhones only; callers handle home-button phones.
enum DisplayCorner {
    static func estimatedRadius(screenWidth: CGFloat) -> CGFloat {
        switch screenWidth {
        case 402...: return 62   // 16 Pro / 17 Pro / Pro Max, Air
        case 393..<402: return 55 // 14 Pro – 16, 15 Plus / Pro Max class
        case 375..<393: return 47 // 12 – 14, X/XS, minis
        default: return 44
        }
    }
}

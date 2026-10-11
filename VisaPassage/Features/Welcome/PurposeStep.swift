import SwiftUI

/// The welcome's purpose step, the landing hero's step 1 (`PurposeScreen`,
/// "What brings you here?"): the purpose cards as a radio group. Choosing one
/// advances to the passport step, and Explore later opens with it applied.
struct PurposeStep: View {
    /// The purpose already chosen, when the visitor came back to change it.
    var current: Purpose?
    let onChoose: (Purpose) -> Void
    /// "Not now": go on without a purpose (lands on Home, as before).
    let onSkip: () -> Void

    @State private var chosen: Purpose?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // `ScreenHeading`: a wrapping title (a large bar title
                    // truncates in Russian) and the lede.
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("What brings you here?")
                            .typography(.h1)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Pick one. You can change it at any time.")
                            .typography(.sm)
                            .foregroundStyle(Theme.textBody)
                    }
                    .padding(.top, Spacing.lg)
                    PurposeCardGrid(selection: chosen ?? current) { purpose in
                        chosen = purpose
                        // Let the ink fill land before the step moves on.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            onChoose(purpose)
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) {
                Button(action: onSkip) {
                    Text("Not now")
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(PressShrinkStyle())
                .padding(.horizontal, Spacing.xl)
                .background(Theme.bg)
                .overlay(alignment: .top) { Divider().overlay(Theme.border) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    PurposeStep(onChoose: { _ in }, onSkip: {})
}

import SwiftUI

/// The title row of a tab's root screen: one size, font and inset on every
/// tab (Geist Medium 34, lined up with the section headers), with an optional
/// brand mark before it and header buttons after it. It's the first row of
/// an inset-grouped `List` (`.tabHeaderRow()`), and the nav bar is hidden on
/// tab roots, so this is the only title they show.
struct TabHeader<Trailing: View>: View {
    let title: Text
    var logo = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                if logo {
                    Image("brand-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .accessibilityHidden(true)
                }
                title
                    .typography(.display)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            // Buttons never change the row's height, so every tab's title
            // sits on the same line whether it has buttons or not.
            trailing()
                .frame(height: 0)
        }
        // Lines up with the section headers.
        .padding(.horizontal, Spacing.xs)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: Text, logo: Bool = false) {
        self.init(title: title, logo: logo) { EmptyView() }
    }
}

extension View {
    /// Place a `TabHeader` as a list row: no insets, no row background.
    func tabHeaderRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

/// A button in a `TabHeader`, in the same format as a nav bar toolbar item
/// (Passport ranking's "Compare"): text in a glass capsule on iOS 26, a
/// bordered capsule before it.
struct HeaderButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(title, action: action)
                .buttonStyle(.glass)
                .foregroundStyle(Theme.ink)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Theme.ink)
        }
    }
}

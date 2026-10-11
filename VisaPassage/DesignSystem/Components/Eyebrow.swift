import SwiftUI

/// Uppercase, wide-tracked eyebrow label that sits above headings.
struct Eyebrow: View {
    private let label: Text

    /// A catalog string, localized.
    init(text: LocalizedStringKey) { label = Text(text) }

    /// An already-resolved string (data, or a label localized upstream).
    init(verbatim: String) { label = Text(verbatim: verbatim) }

    var body: some View {
        label
            .typeRole(.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSoft)
    }
}

/// The "official decisions prevail" honesty disclaimer, shown wherever the app
/// gives eligibility advice. Copy must never promise approval.
struct AdvisoryDisclaimer: View {
    var text: LocalizedStringKey = "Guidance only — eligibility is indicative. Official authority decisions always prevail."
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle").font(.system(size: 13))
            Text(text).typography(.xs)
        }
        .foregroundStyle(Theme.textSoft)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        Eyebrow(text: "Passport strength")
        Text("Where can you go?").typography(.h2)
        AdvisoryDisclaimer()
    }
    .padding()
    .background(Theme.bg)
}

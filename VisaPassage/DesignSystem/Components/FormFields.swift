import SwiftUI

/// Brand input treatment: raised surface fill, 1px hairline border, 12px radius.
struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
    }
}

extension View {
    /// Apply the brand input treatment to any field-like control.
    func inputStyle() -> some View { modifier(InputStyle()) }
}

/// A labelled field: small uppercase label above arbitrary content.
struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .typeRole(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSoft)
            content
        }
    }
}

/// Single-line text input with a label.
struct TextFieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        FormField(label: label) {
            TextField(placeholder, text: $text)
                .typography(.body)
                .foregroundStyle(Theme.ink)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(keyboard == .emailAddress || contentType == .telephoneNumber)
                .inputStyle()
        }
    }
}

/// Menu-style single choice over string options, with a "Not set" escape.
/// `selection` uses `""` for "not set".
struct OptionMenuRow: View {
    let label: String
    @Binding var selection: String
    let options: [String]
    var placeholder: String = String(localized: "Select")
    /// Optional display transform (defaults to capitalized).
    var displayName: (String) -> String = { $0.replacingOccurrences(of: "_", with: " ").capitalized }

    var body: some View {
        FormField(label: label) {
            Menu {
                Button("Not set") { selection = "" }
                ForEach(options, id: \.self) { option in
                    Button(displayName(option)) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection.isEmpty ? placeholder : displayName(selection))
                        .typography(.body)
                        .foregroundStyle(selection.isEmpty ? Theme.textSoft : Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSoft)
                }
                .inputStyle()
            }
        }
    }
}

/// Labelled on/off row.
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).typography(.body).foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
    }
}

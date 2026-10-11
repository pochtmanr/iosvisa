import SwiftUI

/// Deletes the account (App Store guideline 5.1.1(v)). Typing DELETE arms the
/// button, then `POST /api/account/delete` with the session's bearer token
/// removes the account on the server (the same code path as the web settings
/// page) and the app signs out locally.
struct DeleteAccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    static let confirmWord = "DELETE"
    private var armed: Bool { confirmation.trimmingCharacters(in: .whitespaces) == Self.confirmWord }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Delete your account").typography(.h2).foregroundStyle(Theme.ink)
                    Text("This permanently deletes your account, your saved passports and your visa trackers. It can't be undone.")
                        .typography(.body)
                        .foregroundStyle(Theme.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    if let email = auth.userEmail {
                        Text(verbatim: email).typeRole(.monoSm).foregroundStyle(Theme.textSoft)
                    }
                }

                FormField(label: String(localized: "Type DELETE to confirm")) {
                    TextField(text: $confirmation, prompt: Text(verbatim: Self.confirmWord)) { EmptyView() }
                        .typography(.body)
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .submitLabel(.done)
                        .inputStyle()
                }

                if let error {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .medium))
                        Text(error).typography(.xs)
                    }
                    .foregroundStyle(StatusHue.red.softFg)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StatusHue.red.softBg)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }

                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if working { ProgressView().tint(.white) }
                        Text("Delete account").typography(.sm)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(StatusHue.red.solid)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(armed ? 1 : 0.4)
                }
                .buttonStyle(PressShrinkStyle())
                .disabled(!armed || working)
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fieldFocused = true }
    }

    private func delete() async {
        fieldFocused = false
        working = true
        error = nil
        struct Empty: Encodable {}
        struct Done: Decodable { let ok: Bool }
        do {
            _ = try await APIClient().postJSON("/api/account/delete", body: Empty(), as: Done.self)
            SpotlightIndexer.removeAll()
            await auth.signOut()
            dismiss()
        } catch {
            self.error = String(localized: "Couldn't delete your account. Check your connection and try again.")
        }
        working = false
    }
}

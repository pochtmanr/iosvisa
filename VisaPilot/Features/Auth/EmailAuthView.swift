import SwiftUI

/// The email sign-in / sign-up form, reached from the welcome sheet's "Continue
/// with Email" action. Carries the full Password / Magic-link flow against
/// `AuthStore` (logic unchanged from the previous single-screen sign-in). A
/// successful sign-in transitions the whole app via the auth observer; the sheet
/// otherwise dismisses itself.
struct EmailAuthView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case password, magicLink }

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .password
    @State private var isSignUp = false
    @State private var working = false
    @State private var info: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    emailSection
                    feedback
                    AdvisoryDisclaimer()
                    Spacer(minLength: Spacing.xl)
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .navigationTitle(isSignUp ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .onChange(of: mode) { _, _ in clearTransient() }
        .onChange(of: isSignUp) { _, _ in clearTransient() }
        .onDisappear { auth.errorMessage = nil }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Eyebrow(text: "VisaPilot")
            Text("Continue with email")
                .typography(.h2)
                .foregroundStyle(Theme.ink)
            Text("Use a password, or have a one-time sign-in link emailed to you.")
                .typography(.body)
                .foregroundStyle(Theme.textBody)
        }
    }

    private var emailSection: some View {
        VStack(spacing: Spacing.md) {
            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .typography(.body)
                .inputStyle()

            Picker("Sign-in method", selection: $mode) {
                Text("Password").tag(Mode.password)
                Text("Magic link").tag(Mode.magicLink)
            }
            .pickerStyle(.segmented)

            if mode == .password {
                passwordControls
            } else {
                magicLinkControls
            }
        }
    }

    private var passwordControls: some View {
        VStack(spacing: Spacing.md) {
            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .typography(.body)
                .inputStyle()

            PrimaryButton(
                title: isSignUp ? "Create account" : "Sign in",
                loading: working,
                enabled: canSubmitPassword
            ) { submitPassword() }

            HStack {
                Button(isSignUp ? "Have an account? Sign in" : "New here? Create account") {
                    isSignUp.toggle()
                }
                .typography(.sm)
                .foregroundStyle(Theme.ink)
                Spacer()
                if !isSignUp {
                    Button("Forgot password?") { submitReset() }
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                }
            }
        }
    }

    private var magicLinkControls: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(
                title: "Email me a magic link",
                icon: "envelope",
                loading: working,
                enabled: isValidEmail && !working
            ) { submitMagicLink() }
        }
    }

    @ViewBuilder private var feedback: some View {
        if let info {
            noticeCard(text: info, hue: .green, icon: "checkmark.circle")
        }
        if let error = auth.errorMessage {
            noticeCard(text: error, hue: .red, icon: "exclamationmark.circle")
        }
    }

    private func noticeCard(text: String, hue: StatusHue, icon: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
            Text(text).typography(.xs)
        }
        .foregroundStyle(hue.softFg)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hue.softBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Validation

    private var isValidEmail: Bool { email.contains("@") && email.contains(".") }
    private var canSubmitPassword: Bool {
        isValidEmail && password.count >= (isSignUp ? 8 : 1) && !working
    }

    // MARK: Actions

    private func submitPassword() {
        clearTransient()
        working = true
        Task {
            if isSignUp {
                let outcome = await auth.signUpWithEmail(email: email, password: password)
                if outcome == .confirmationSent {
                    info = "Check your email to confirm your account, then sign in."
                }
                // .signedIn transitions automatically via the auth observer.
            } else {
                _ = await auth.signInWithEmail(email: email, password: password)
            }
            working = false
        }
    }

    private func submitMagicLink() {
        clearTransient()
        working = true
        Task {
            if await auth.sendMagicLink(email: email) {
                info = "We've emailed a sign-in link to \(email). Open it on this device."
            }
            working = false
        }
    }

    private func submitReset() {
        guard isValidEmail else {
            auth.errorMessage = "Enter your email first, then tap Forgot password."
            return
        }
        clearTransient()
        working = true
        Task {
            if await auth.sendPasswordReset(email: email) {
                info = "If that address has an account, a reset link is on its way."
            }
            working = false
        }
    }

    private func clearTransient() {
        info = nil
        auth.errorMessage = nil
    }
}
